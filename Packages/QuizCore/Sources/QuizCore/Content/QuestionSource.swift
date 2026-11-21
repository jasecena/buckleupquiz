import Foundation

/// Where questions come from. v1 ships `DirectoryQuestionSource` reading the bundled
/// `Content/` folder. A future remote content-pack source plugs in here (ADR-0012).
public protocol QuestionSource: Sendable {
    func loadBank() async throws -> QuestionBank
}

public enum QuestionSourceError: Error, Equatable, CustomStringConvertible {
    case missingCatalogue(URL)
    case unknownTopic(questionID: String, topic: String)
    case duplicateQuestionID(String)
    case invalidFile(name: String, reason: String)

    public var description: String {
        switch self {
        case .missingCatalogue(let url): "Topic catalogue not found at \(url.path)"
        case .unknownTopic(let id, let topic): "Question \(id) references unknown topic '\(topic)'"
        case .duplicateQuestionID(let id): "Duplicate question id \(id)"
        case .invalidFile(let name, let reason): "Could not read \(name): \(reason)"
        }
    }
}

/// Reads `<root>/topics.json` and every `<root>/questions/*.json` (each an array of questions).
public struct DirectoryQuestionSource: QuestionSource {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func loadBank() async throws -> QuestionBank {
        try loadBankSync()
    }

    /// Synchronous variant, handy for tests and command-line tools.
    public func loadBankSync() throws -> QuestionBank {
        let decoder = JSONDecoder()
        let catalogueURL = root.appendingPathComponent("topics.json")
        guard FileManager.default.fileExists(atPath: catalogueURL.path) else {
            throw QuestionSourceError.missingCatalogue(catalogueURL)
        }
        let topics = try decode([Topic].self, from: catalogueURL, using: decoder)
        let topicIDs = Set(topics.map(\.id))

        let questionsDir = root.appendingPathComponent("questions")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: questionsDir, includingPropertiesForKeys: nil
        )) ?? []

        var questions: [Question] = []
        var seen = Set<String>()
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
            for q in try decode([Question].self, from: file, using: decoder) {
                guard topicIDs.contains(q.topic) else {
                    throw QuestionSourceError.unknownTopic(questionID: q.id, topic: q.topic)
                }
                guard seen.insert(q.id).inserted else {
                    throw QuestionSourceError.duplicateQuestionID(q.id)
                }
                questions.append(q)
            }
        }
        return QuestionBank(topics: topics, questions: questions)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL, using decoder: JSONDecoder) throws -> T {
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch {
            throw QuestionSourceError.invalidFile(name: url.lastPathComponent, reason: String(describing: error))
        }
    }
}

/// A fixed bank, for previews and tests.
public struct InMemoryQuestionSource: QuestionSource {
    public let bank: QuestionBank
    public init(bank: QuestionBank) { self.bank = bank }
    public func loadBank() async throws -> QuestionBank { bank }
}
