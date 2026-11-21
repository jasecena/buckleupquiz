import Foundation
import Observation

/// One anonymous diagnostic event (ADR-0020). It never holds names, ages, answers, what was
/// heard, or any identifier for the device or the family.
struct TelemetryEvent: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var fields: [String: String]
    /// Rounded down to the hour.
    var at: Date
}

/// Something that can note a diagnostic event. Fakes implement it in tests.
@MainActor
protocol TelemetryRecording: AnyObject {
    func record(_ name: String, _ fields: [String: String])
}

/// Anonymous error reports (ADR-0020). Events queue on the device and are sent in batches to
/// our own endpoint when one is configured; until then they stay visible in Settings →
/// Diagnostics. No third-party SDK, no identifiers, nothing that could identify a child.
@MainActor
@Observable
final class Telemetry: TelemetryRecording {
    static let maxQueued = 300
    static let maxFieldLength = 500
    /// MetricKit crash and hang reports are bigger (call stacks).
    static let maxReportLength = 60_000
    static let batchSize = 20

    /// Events not sent yet, oldest first.
    private(set) var pending: [TelemetryEvent] = []
    private(set) var lastSent: Date?
    private(set) var lastError: String?

    let endpoint: URL?
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let send: @Sendable (URLRequest) async throws -> Int
    @ObservationIgnored private var isSending = false
    /// Random per launch, so one launch's events can be read together. Never stored.
    let launchID = UUID().uuidString

    init(
        endpoint: URL?,
        fileURL: URL? = Telemetry.defaultFileURL,
        isEnabled: @escaping @MainActor () -> Bool,
        send: @escaping @Sendable (URLRequest) async throws -> Int = Telemetry.urlSessionSend
    ) {
        self.endpoint = endpoint
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        self.send = send
        load()
    }

    /// The endpoint from Info.plist (`BUQTelemetryURL`, set from the `TELEMETRY_URL` build
    /// setting). Empty means "keep reports on the device".
    static var configuredEndpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BUQTelemetryURL") as? String,
              value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

    static var defaultFileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("telemetry.json")
    }

    // MARK: Recording

    func record(_ name: String, _ fields: [String: String] = [:]) {
        record(name, fields, maxLength: Self.maxFieldLength)
    }

    func record(_ name: String, _ fields: [String: String], maxLength: Int) {
        guard isEnabled() else { return }
        let trimmed = fields.mapValues { String($0.prefix(maxLength)) }
        pending.append(TelemetryEvent(name: name, fields: trimmed, at: Self.hour(of: .now)))
        if pending.count > Self.maxQueued { pending.removeFirst(pending.count - Self.maxQueued) }
        save()
    }

    /// Called when the parent turns reports off: nothing queued is kept.
    func clear() {
        pending.removeAll()
        save()
    }

    // MARK: Sending

    /// Sends queued events in batches. Quietly gives up on any failure and tries next time.
    func flush() async {
        guard isEnabled() else { return clear() }
        guard let endpoint, !isSending, !pending.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        while !pending.isEmpty {
            let batch = Array(pending.prefix(Self.batchSize))
            var request = URLRequest(url: endpoint, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? Self.encoder.encode(Self.payload(batch, launchID: launchID))
            do {
                let status = try await send(request)
                guard (200..<300).contains(status) else {
                    lastError = "Server said \(status)"
                    return
                }
            } catch {
                lastError = error.localizedDescription
                return
            }
            let sent = Set(batch.map(\.id))
            pending.removeAll { sent.contains($0.id) }
            lastSent = .now
            lastError = nil
            save()
        }
    }

    /// Everything that would be sent, as readable JSON (Settings → Diagnostics → Share).
    var report: String {
        let data = (try? Self.encoder.encode(Self.payload(pending, launchID: launchID))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    struct Payload: Encodable {
        var schema = 1
        var app: String
        var build: String
        var os: String
        var device: String
        var launch: String
        var events: [TelemetryEvent]
    }

    static func payload(_ events: [TelemetryEvent], launchID: String) -> Payload {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Payload(
            app: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            os: "iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            device: deviceModel,
            launch: launchID,
            events: events)
    }

    /// The hardware model, e.g. "iPhone15,3". Not an identifier: millions of phones share it.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func hour(of date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    nonisolated static func urlSessionSend(_ request: URLRequest) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let (_, response) = try await URLSession(configuration: configuration).data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // MARK: Storage

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        pending = (try? decoder.decode([TelemetryEvent].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else if let data = try? Self.encoder.encode(pending) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
