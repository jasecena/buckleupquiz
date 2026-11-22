import Foundation
import Testing
@testable import QuizCore

/// Downloaded question sets (ADR-0031): the manifest checks and the fallback to bundled questions.
@Suite("Content manifest")
struct ContentManifestTests {
    static let hash = String(repeating: "a", count: 64)

    static func manifest(paths: [String] = ["topics.json", "questions/animals.json"],
                         minAppVersion: String = "0.4.0", format: Int = 1) -> ContentManifest {
        ContentManifest(format: format, version: 1_790_000_000, minAppVersion: minAppVersion,
                        files: paths.map { .init(path: $0, sha256: hash, size: 100) })
    }

    @Test func aGoodManifestPasses() throws {
        try Self.manifest().check(appVersion: "0.4.0")
        try Self.manifest().check(appVersion: "0.10.0")
    }

    @Test func olderAppsAreRefused() {
        #expect(throws: ContentManifest.Problem.needsNewerApp("0.4.0")) {
            try Self.manifest().check(appVersion: "0.3.9")
        }
    }

    @Test func unknownFormatsAreRefused() {
        #expect(throws: ContentManifest.Problem.unknownFormat(2)) {
            try Self.manifest(format: 2).check(appVersion: "1.0")
        }
    }

    @Test(arguments: ["../topics.json", "/etc/passwd", "questions/../../x.json", "questions/.json",
                      "questions/Animals.json", "questions/a/b.json", "questions/x.json.exe", "topics.JSON",
                      "manifest.json", "questions/-x.json", "questions/ä.json", ""])
    func unsafePathsAreRefused(_ path: String) {
        #expect(!ContentManifest.isSafePath(path))
        #expect(throws: ContentManifest.Problem.badPath(path)) {
            try Self.manifest(paths: ["topics.json", "questions/animals.json", path]).check(appVersion: "1.0")
        }
    }

    @Test(arguments: ["topics.json", "questions/animals.json", "questions/aussie-history.json", "questions/k9.json"])
    func safePaths(_ path: String) {
        #expect(ContentManifest.isSafePath(path))
    }

    @Test func needsTheCatalogueAndSomeQuestions() {
        #expect(throws: ContentManifest.Problem.noCatalogue) {
            try Self.manifest(paths: ["questions/animals.json"]).check(appVersion: "1.0")
        }
        #expect(throws: ContentManifest.Problem.noQuestions) {
            try Self.manifest(paths: ["topics.json"]).check(appVersion: "1.0")
        }
    }

    @Test func badHashesSizesAndDuplicatesAreRefused() {
        var m = Self.manifest()
        m.files[1].sha256 = String(repeating: "A", count: 64)
        #expect(throws: ContentManifest.Problem.badHash("questions/animals.json")) { try m.check(appVersion: "1.0") }

        m = Self.manifest()
        m.files[1].size = ContentManifest.maxFileSize + 1
        #expect(throws: ContentManifest.Problem.badSize("questions/animals.json")) { try m.check(appVersion: "1.0") }

        m = Self.manifest(paths: ["topics.json", "questions/animals.json", "questions/animals.json"])
        #expect(throws: ContentManifest.Problem.duplicatePath("questions/animals.json")) { try m.check(appVersion: "1.0") }
    }

    @Test func onlyChangedFilesAreDownloaded() {
        let old = Self.manifest(paths: ["topics.json", "questions/animals.json", "questions/space.json"])
        var new = Self.manifest(paths: ["topics.json", "questions/animals.json", "questions/space.json", "questions/food.json"])
        new.files[1].sha256 = String(repeating: "b", count: 64)
        #expect(new.filesToDownload(comparedWith: old).map(\.path) == ["questions/animals.json", "questions/food.json"])
        #expect(new.filesToDownload(comparedWith: nil).count == 4)
    }

    @Test func decodesTheJSONThePublishScriptWrites() throws {
        let json = """
        {"format": 1, "version": 1790000000, "minAppVersion": "0.4.0",
         "files": [{"path": "topics.json", "sha256": "\(Self.hash)", "size": 12}]}
        """
        let m = try JSONDecoder().decode(ContentManifest.self, from: Data(json.utf8))
        #expect(m.version == 1_790_000_000)
        #expect(m.files.first?.size == 12)
    }

    @Test(arguments: [("0.3.9", "0.3.10", ComparisonResult.orderedAscending), ("0.4", "0.4.0", .orderedSame),
                      ("1.0.0", "0.9.9", .orderedDescending), ("0.4.0", "0.4.1", .orderedAscending)])
    func versionsCompareByNumber(_ a: String, _ b: String, _ expected: ComparisonResult) {
        #expect(AppVersion.compare(a, b) == expected)
    }
}

@Suite("Fallback question source")
struct FallbackQuestionSourceTests {
    struct Failing: QuestionSource {
        func loadBank() async throws -> QuestionBank { throw QuestionSourceError.invalidFile(name: "x", reason: "bad") }
    }

    actor Reasons {
        var all: [String] = []
        func add(_ e: Error) { all.append(String(describing: e)) }
    }

    @Test func usesTheDownloadWhenItLoads() async throws {
        let source = FallbackQuestionSource(primary: InMemoryQuestionSource(bank: sampleBank(perBand: 2)),
                                            fallback: InMemoryQuestionSource(bank: sampleBank(perBand: 1)))
        #expect(try await source.loadBank().questions.count == 6)
    }

    @Test func fallsBackWhenTheDownloadFailsOrIsEmpty() async throws {
        let reasons = Reasons()
        for primary in [Failing() as any QuestionSource, InMemoryQuestionSource(bank: .empty)] {
            let source = FallbackQuestionSource(primary: primary,
                                                fallback: InMemoryQuestionSource(bank: sampleBank(perBand: 1)),
                                                onFallback: { await reasons.add($0) })
            #expect(try await source.loadBank().questions.count == 3)
        }
        #expect(await reasons.all.count == 2)
    }
}
