/// An in-memory, indexed set of topics and questions.
public struct QuestionBank: Sendable {
    public let topics: [Topic]
    public let questions: [Question]
    private let byTopicAndBand: [Key: [Question]]

    private struct Key: Hashable { let topic: String; let band: AgeBand }

    public init(topics: [Topic], questions: [Question]) {
        self.topics = topics
        self.questions = questions
        self.byTopicAndBand = Dictionary(grouping: questions) { Key(topic: $0.topic, band: $0.ageBand) }
    }

    public static let empty = QuestionBank(topics: [], questions: [])

    public func topic(id: String) -> Topic? { topics.first { $0.id == id } }

    public func questions(topic: String, ageBand: AgeBand) -> [Question] {
        byTopicAndBand[Key(topic: topic, band: ageBand)] ?? []
    }

    /// Every question in a topic, all age bands.
    public func questions(topic: String) -> [Question] {
        AgeBand.allCases.flatMap { questions(topic: topic, ageBand: $0) }
    }

    public func questions(topics: some Sequence<String>, ageBand: AgeBand) -> [Question] {
        topics.flatMap { questions(topic: $0, ageBand: ageBand) }
    }

    /// Number of questions for a topic, optionally limited to one age band.
    public func questionCount(topic: String, ageBand: AgeBand? = nil) -> Int {
        if let ageBand { return questions(topic: topic, ageBand: ageBand).count }
        return AgeBand.allCases.reduce(0) { $0 + questions(topic: topic, ageBand: $1).count }
    }
}
