import Foundation

/// The list of files in one published question set (ADR-0031). It's signed on the server side;
/// the app checks the signature before it reads anything here (that part is in the app, since
/// QuizCore is Foundation-only).
///
/// Layout on the CDN, under `content/v1/`:
/// - `current.json`: this manifest's JSON and its signature, in one file
/// - `sets/<version>/topics.json` and `sets/<version>/questions/<topic>.json`
public struct ContentManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        /// Relative to the set's folder: `topics.json` or `questions/<topic>.json`.
        public var path: String
        /// Lowercase hex SHA-256 of the file's bytes.
        public var sha256: String
        public var size: Int

        public init(path: String, sha256: String, size: Int) {
            self.path = path
            self.sha256 = sha256
            self.size = size
        }
    }

    /// The manifest's own layout. An app only reads the formats it knows.
    public var format: Int
    /// Only goes up: the Unix time of the git commit the set was built from. The bundled set has
    /// one too (`BUQContentVersion`), so a newer app update wins over an older download.
    public var version: Int
    /// The oldest app version that can read this set ("0.4.0").
    public var minAppVersion: String
    public var files: [File]

    public init(format: Int = ContentManifest.currentFormat, version: Int, minAppVersion: String, files: [File]) {
        self.format = format
        self.version = version
        self.minAppVersion = minAppVersion
        self.files = files
    }

    public static let currentFormat = 1
    public static let maxFiles = 200
    public static let maxFileSize = 2_000_000
    public static let maxManifestSize = 100_000

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case unknownFormat(Int)
        case needsNewerApp(String)
        case badPath(String)
        case duplicatePath(String)
        case badHash(String)
        case badSize(String)
        case noCatalogue
        case noQuestions
        case tooManyFiles

        /// Short and free of content, for anonymous error reports (ADR-0020).
        public var description: String {
            switch self {
            case .unknownFormat: "unknownFormat"
            case .needsNewerApp: "needsNewerApp"
            case .badPath: "badPath"
            case .duplicatePath: "duplicatePath"
            case .badHash: "badHash"
            case .badSize: "badSize"
            case .noCatalogue: "noCatalogue"
            case .noQuestions: "noQuestions"
            case .tooManyFiles: "tooManyFiles"
            }
        }
    }

    /// Throws the first reason this app can't use the set. Paths are checked strictly, so a
    /// manifest can never make the app write outside the set's folder.
    public func check(appVersion: String) throws(Problem) {
        guard format == Self.currentFormat else { throw .unknownFormat(format) }
        guard AppVersion.compare(appVersion, minAppVersion) != .orderedAscending else {
            throw .needsNewerApp(minAppVersion)
        }
        guard files.count <= Self.maxFiles else { throw .tooManyFiles }
        var seen = Set<String>()
        for file in files {
            guard Self.isSafePath(file.path) else { throw .badPath(file.path) }
            guard seen.insert(file.path).inserted else { throw .duplicatePath(file.path) }
            guard Self.isHexSHA256(file.sha256) else { throw .badHash(file.path) }
            guard (1...Self.maxFileSize).contains(file.size) else { throw .badSize(file.path) }
        }
        guard seen.contains("topics.json") else { throw .noCatalogue }
        guard seen.contains(where: { $0.hasPrefix("questions/") }) else { throw .noQuestions }
    }

    /// `topics.json`, or `questions/` plus a lowercase name of letters, digits and dashes, `.json`.
    public static func isSafePath(_ path: String) -> Bool {
        if path == "topics.json" { return true }
        let prefix = "questions/", suffix = ".json"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return false }
        let name = path.dropFirst(prefix.count).dropLast(suffix.count)
        return !name.isEmpty && name.count <= 64 && !name.hasPrefix("-")
            && name.unicodeScalars.allSatisfy { lowerLetters.contains($0) || digits.contains($0) || $0 == "-" }
    }

    static func isHexSHA256(_ value: String) -> Bool {
        value.unicodeScalars.count == 64
            && value.unicodeScalars.allSatisfy { digits.contains($0) || ("a"..."f").contains($0) }
    }

    private static let lowerLetters: ClosedRange<Unicode.Scalar> = "a"..."z"
    private static let digits: ClosedRange<Unicode.Scalar> = "0"..."9"

    /// The files that differ from `current` (same path and hash can be copied on the phone).
    public func filesToDownload(comparedWith current: ContentManifest?) -> [File] {
        let have = Set((current?.files ?? []).map { "\($0.path)#\($0.sha256)" })
        return files.filter { !have.contains("\($0.path)#\($0.sha256)") }
    }
}

/// Dotted app versions ("0.3.10" > "0.3.9"). Missing parts count as 0; anything that isn't a
/// number counts as 0 too.
public enum AppVersion {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// Reads `primary`, and if that fails, `fallback` (ADR-0031: a downloaded set that can't be read
/// never stops a game; the bundled questions take over). `onFallback` gets the reason.
public struct FallbackQuestionSource: QuestionSource {
    public let primary: any QuestionSource
    public let fallback: any QuestionSource
    public let onFallback: @Sendable (Error) async -> Void

    public init(primary: any QuestionSource, fallback: any QuestionSource,
                onFallback: @escaping @Sendable (Error) async -> Void = { _ in }) {
        self.primary = primary
        self.fallback = fallback
        self.onFallback = onFallback
    }

    public func loadBank() async throws -> QuestionBank {
        do {
            let bank = try await primary.loadBank()
            guard !bank.questions.isEmpty else { throw ContentManifest.Problem.noQuestions }
            return bank
        } catch {
            await onFallback(error)
            return try await fallback.loadBank()
        }
    }
}
