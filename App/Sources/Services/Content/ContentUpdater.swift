import CryptoKit
import Foundation
import QuizCore

/// New questions without an app update (ADR-0031). Checks our CDN for a newer signed question
/// set, at most every 12 hours and never during a game, downloads only the changed files,
/// checks everything, and keeps the result on the phone. Games always play from the phone; the
/// bundled questions are the fallback.
///
/// The request is a plain GET: no ids, names, counts or device details.
@MainActor
final class ContentUpdater {
    struct Config: Sendable {
        /// `https://api.buckleupquiz.com/content/v1/`
        var baseURL: URL
        var publicKey: Curve25519.Signing.PublicKey
        /// This app's version, checked against the set's `minAppVersion`.
        var appVersion: String
        /// The bundled set's version (`BUQContentVersion`). A download must be newer.
        var bundledVersion: Int
    }

    enum Outcome: Equatable {
        /// Not checked: too soon since the last check.
        case notDue
        /// The newest set is already here (or the bundled one is newer).
        case upToDate
        /// A new set was installed at this folder; load it for the next game.
        case installed(URL)
        /// Couldn't reach the server (no signal is normal in a car). Tried again next time.
        case offline
        /// The download was refused (bad signature, hash, path, unreadable questions...).
        case refused(String)
    }

    /// `current.json`: the manifest's exact bytes and their signature, in one file so a phone
    /// never gets one without the other.
    struct SignedManifest: Codable {
        var manifest: String
        var signature: String
    }

    static let checkInterval: TimeInterval = 12 * 60 * 60
    private static let lastCheckKey = "content.lastCheck"

    let config: Config
    let store: ContentStore
    private let fetch: @Sendable (URL) async throws -> Data
    private let defaults: UserDefaults
    private weak var telemetry: (any TelemetryRecording)?
    private var isChecking = false

    init(config: Config, store: ContentStore, defaults: UserDefaults = .standard,
         telemetry: (any TelemetryRecording)? = nil,
         fetch: @escaping @Sendable (URL) async throws -> Data = ContentUpdater.download) {
        self.config = config
        self.store = store
        self.defaults = defaults
        self.telemetry = telemetry
        self.fetch = fetch
    }

    /// The live updater, or nil when this build has no content URL or public key (downloads off).
    static func live(telemetry: any TelemetryRecording) -> ContentUpdater? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let url = (info["BUQContentURL"] as? String).flatMap(URL.init(string:)),
              url.scheme == "https",
              let key = (info["BUQContentPublicKey"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              let store = ContentStore.live() else { return nil }
        let config = Config(baseURL: url, publicKey: publicKey,
                            appVersion: info["CFBundleShortVersionString"] as? String ?? "0",
                            bundledVersion: bundledVersion(info))
        return ContentUpdater(config: config, store: store, telemetry: telemetry)
    }

    static func bundledVersion(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> Int {
        Int(info["BUQContentVersion"] as? String ?? "") ?? 0
    }

    /// The downloaded set to play from, if it's newer than the bundled one and this app can read it.
    func preferredSet() -> URL? {
        guard let set = store.active(),
              set.manifest.version > config.bundledVersion,
              (try? set.manifest.check(appVersion: config.appVersion)) != nil else { return nil }
        return set.folder
    }

    func checkIfDue(now: Date = .now) async -> Outcome {
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           now.timeIntervalSince(last) < Self.checkInterval, now >= last { return .notDue }
        guard !isChecking else { return .notDue }
        isChecking = true
        defer { isChecking = false }
        let outcome = await check()
        switch outcome {
        case .offline: break // try again when the app is next opened
        case .refused(let reason):
            defaults.set(now, forKey: Self.lastCheckKey)
            telemetry?.record("content.updateRefused", ["reason": reason])
        default:
            defaults.set(now, forKey: Self.lastCheckKey)
        }
        if case .installed = outcome { telemetry?.record("content.updated", [:]) }
        return outcome
    }

    private func check() async -> Outcome {
        let currentData: Data
        do {
            currentData = try await fetch(config.baseURL.appendingPathComponent("current.json"))
        } catch {
            return .offline
        }
        guard currentData.count <= 2 * ContentManifest.maxManifestSize else { return .refused("manifestTooBig") }
        guard let envelope = try? JSONDecoder().decode(SignedManifest.self, from: currentData),
              let manifestData = Data(base64Encoded: envelope.manifest),
              let signature = Data(base64Encoded: envelope.signature) else { return .refused("unreadableManifest") }
        guard config.publicKey.isValidSignature(signature, for: manifestData) else { return .refused("badSignature") }
        let manifest: ContentManifest
        do {
            manifest = try JSONDecoder().decode(ContentManifest.self, from: manifestData)
            try manifest.check(appVersion: config.appVersion)
        } catch let problem as ContentManifest.Problem {
            // Too new for this app isn't a fault: the app update brings it.
            if case .needsNewerApp = problem { return .upToDate }
            return .refused(problem.description)
        } catch {
            return .refused("unreadableManifest")
        }
        let current = store.active()
        guard manifest.version > max(config.bundledVersion, current?.manifest.version ?? 0) else { return .upToDate }

        let setURL = config.baseURL.appendingPathComponent("sets/\(manifest.version)")
        var downloaded: [String: Data] = [:]
        for file in manifest.filesToDownload(comparedWith: current?.manifest) {
            let data: Data
            do { data = try await fetch(setURL.appendingPathComponent(file.path)) } catch { return .offline }
            guard data.count == file.size, Self.sha256(data) == file.sha256 else { return .refused("badFile") }
            downloaded[file.path] = data
        }
        do {
            return .installed(try store.install(manifest, downloaded: downloaded))
        } catch let problem as ContentStore.Problem {
            return .refused(problem.rawValue)
        } catch {
            return .refused("unreadableQuestions")
        }
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A plain GET with no cookies and no shared cache; only 200 counts.
    nonisolated static let download: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}

/// Downloaded question sets on the phone: Application Support/DownloadedContent, left out of
/// the device backup (they can be downloaded again). At most the active set and the one being
/// installed.
struct ContentStore: Sendable {
    enum Problem: String, Error {
        case missingFile
        case unreadableQuestions
    }

    let root: URL

    static func live() -> ContentStore? {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true) else { return nil }
        return ContentStore(root: support.appendingPathComponent("DownloadedContent", isDirectory: true))
    }

    private var activeURL: URL { root.appendingPathComponent("active.json") }
    private func folder(_ version: Int) -> URL { root.appendingPathComponent("sets/\(version)", isDirectory: true) }

    /// The installed set: its manifest and its folder (with `topics.json` and `questions/`).
    func active() -> (manifest: ContentManifest, folder: URL)? {
        guard let data = try? Data(contentsOf: activeURL),
              let manifest = try? JSONDecoder().decode(ContentManifest.self, from: data) else { return nil }
        let dir = folder(manifest.version)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("topics.json").path) else { return nil }
        return (manifest, dir)
    }

    /// Writes the new set (downloaded files, plus unchanged ones copied from the active set),
    /// loads it like the app will, and only then makes it active. Older sets are removed.
    func install(_ manifest: ContentManifest, downloaded: [String: Data]) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try? rootURL.setResourceValues(values)

        let current = active()
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging.appendingPathComponent("questions"), withIntermediateDirectories: true)
        for file in manifest.files {
            let target = staging.appendingPathComponent(file.path)
            if let data = downloaded[file.path] {
                try data.write(to: target)
            } else if let current, current.manifest.files.contains(file) {
                try fm.copyItem(at: current.folder.appendingPathComponent(file.path), to: target)
            } else {
                throw Problem.missingFile
            }
        }
        // The same reader the game uses: unknown topics or duplicate ids are refused here.
        guard let bank = try? DirectoryQuestionSource(root: staging).loadBankSync(), !bank.questions.isEmpty else {
            try? fm.removeItem(at: staging)
            throw Problem.unreadableQuestions
        }

        let target = folder(manifest.version)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: staging, to: target)
        try JSONEncoder().encode(manifest).write(to: activeURL, options: .atomic)

        let sets = root.appendingPathComponent("sets", isDirectory: true)
        for old in (try? fm.contentsOfDirectory(at: sets, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != String(manifest.version) {
            try? fm.removeItem(at: old)
        }
        return target
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
