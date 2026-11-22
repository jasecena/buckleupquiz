import CryptoKit
import Foundation
import QuizCore
import Testing
@testable import BuckleUpQuiz

/// New questions without an app update (ADR-0031): only signed, matching, readable sets are used.
@MainActor
struct ContentUpdaterTests {
    nonisolated static let base = URL(string: "https://example.invalid/content/v1/")!

    /// A fake CDN: path → bytes. Missing paths throw, like a failed download.
    final class Server: @unchecked Sendable {
        var files: [String: Data] = [:]
        var requested: [String] = []
        var offline = false
        func fetch(_ url: URL) throws -> Data {
            let path = String(url.absoluteString.dropFirst(ContentUpdaterTests.base.absoluteString.count))
            requested.append(path)
            if offline { throw URLError(.notConnectedToInternet) }
            guard let data = files[path] else { throw URLError(.badServerResponse) }
            return data
        }
    }

    let key = Curve25519.Signing.PrivateKey()
    let server = Server()
    let telemetry = FakeTelemetry()
    let defaults = UserDefaults(suiteName: "content-\(UUID())")!
    let store = ContentStore(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("content-\(UUID())", isDirectory: true))

    func makeUpdater(bundledVersion: Int = 100, appVersion: String = "0.4.0", publicKey: Curve25519.Signing.PublicKey? = nil) -> ContentUpdater {
        let server = server
        return ContentUpdater(
            config: .init(baseURL: Self.base, publicKey: publicKey ?? key.publicKey, appVersion: appVersion,
                          bundledVersion: bundledVersion),
            store: store, defaults: defaults, telemetry: telemetry, fetch: { try server.fetch($0) })
    }

    static func files(questions: Int, topic: String = "animals") throws -> [String: Data] {
        let bank = makeBank(questions: questions)
        let encoder = JSONEncoder()
        return ["topics.json": try encoder.encode(bank.topics),
                "questions/\(topic).json": try encoder.encode(bank.questions)]
    }

    /// Publishes a set the way the workflow does: files, then the signed manifest.
    func publish(version: Int, files: [String: Data], minAppVersion: String = "0.4.0", signWith signer: Curve25519.Signing.PrivateKey? = nil) throws {
        let manifest = ContentManifest(version: version, minAppVersion: minAppVersion, files: files.keys.sorted().map {
            .init(path: $0, sha256: ContentUpdater.sha256(files[$0]!), size: files[$0]!.count)
        })
        for (path, data) in files { server.files["sets/\(version)/\(path)"] = data }
        let json = try JSONEncoder().encode(manifest)
        let signature = try (signer ?? key).signature(for: json)
        server.files["current.json"] = try JSONEncoder().encode(
            ContentUpdater.SignedManifest(manifest: json.base64EncodedString(), signature: signature.base64EncodedString()))
    }

    @Test func installsANewerSignedSet() async throws {
        try publish(version: 200, files: Self.files(questions: 3))
        let updater = makeUpdater()
        let outcome = await updater.checkIfDue()
        guard case .installed(let folder) = outcome else { Issue.record("got \(outcome)"); return }
        #expect(try DirectoryQuestionSource(root: folder).loadBankSync().questions.count == 3)
        #expect(updater.preferredSet() == folder)
        #expect(telemetry.names == ["content.updated"])
    }

    @Test func checksAtMostEvery12Hours() async throws {
        try publish(version: 200, files: Self.files(questions: 3))
        let updater = makeUpdater()
        let now = Date()
        _ = await updater.checkIfDue(now: now)
        #expect(await updater.checkIfDue(now: now.addingTimeInterval(60 * 60)) == .notDue)
        #expect(await updater.checkIfDue(now: now.addingTimeInterval(13 * 60 * 60)) == .upToDate)
    }

    @Test func offlineIsQuietAndTriesAgainNextTime() async throws {
        server.offline = true
        let updater = makeUpdater()
        #expect(await updater.checkIfDue() == .offline)
        #expect(telemetry.names.isEmpty)
        server.offline = false
        try publish(version: 200, files: Self.files(questions: 3))
        guard case .installed = await updater.checkIfDue() else { Issue.record("expected install"); return }
    }

    @Test func refusesAWrongSignature() async throws {
        try publish(version: 200, files: Self.files(questions: 3), signWith: Curve25519.Signing.PrivateKey())
        #expect(await makeUpdater().checkIfDue() == .refused("badSignature"))
        #expect(telemetry.names == ["content.updateRefused"])
        #expect(store.active() == nil)
    }

    @Test func refusesAChangedFile() async throws {
        try publish(version: 200, files: Self.files(questions: 3))
        server.files["sets/200/questions/animals.json"] = try Self.files(questions: 4)["questions/animals.json"]
        #expect(await makeUpdater().checkIfDue() == .refused("badFile"))
        #expect(store.active() == nil)
    }

    @Test func refusesQuestionsTheGameCantRead() async throws {
        var files = try Self.files(questions: 3)
        files["questions/animals.json"] = Data("not json".utf8)
        try publish(version: 200, files: files)
        #expect(await makeUpdater().checkIfDue() == .refused("unreadableQuestions"))
        #expect(store.active() == nil)
    }

    @Test func aSetForANewerAppWaitsForTheUpdate() async throws {
        try publish(version: 200, files: Self.files(questions: 3), minAppVersion: "0.5.0")
        #expect(await makeUpdater(appVersion: "0.4.0").checkIfDue() == .upToDate)
        #expect(telemetry.names.isEmpty)
    }

    @Test func theBundledSetWinsWhenItsNewer() async throws {
        try publish(version: 200, files: Self.files(questions: 3))
        guard case .installed = await makeUpdater(bundledVersion: 100).checkIfDue() else {
            Issue.record("expected install"); return
        }
        // After an app update whose bundled questions are newer, the download is ignored.
        #expect(makeUpdater(bundledVersion: 300).preferredSet() == nil)
    }

    @Test func downloadsOnlyChangedFilesAndKeepsOneSet() async throws {
        var files = try Self.files(questions: 3)
        files["questions/space.json"] = try JSONEncoder().encode([Question]())
        try publish(version: 200, files: files)
        let first = makeUpdater()
        _ = await first.checkIfDue()

        files["questions/animals.json"] = try Self.files(questions: 5)["questions/animals.json"]
        try publish(version: 300, files: files)
        server.requested = []
        let later = makeUpdater()
        defaults.removeObject(forKey: "content.lastCheck")
        guard case .installed(let folder) = await later.checkIfDue() else { Issue.record("expected install"); return }
        #expect(server.requested == ["current.json", "sets/300/questions/animals.json"])
        #expect(try DirectoryQuestionSource(root: folder).loadBankSync().questions.count == 5)
        let sets = try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent("sets").path)
        #expect(sets == ["300"])
    }
}
