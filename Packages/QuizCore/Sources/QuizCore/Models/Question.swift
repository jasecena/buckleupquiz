/// One question from the content bank. Mirrors the JSON schema in FEATURES §4.1.
public struct Question: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var topic: String
    public var ageBand: AgeBand
    public var type: QuestionType
    public var question: String
    public var options: [String]?
    /// The canonical answer. `nil` only for `talkAbout`.
    public var answer: String?
    public var acceptedAnswers: [String]
    public var funFact: String?
    /// Read after the answer in place of `funFact` (values topics).
    public var explanation: String?
    public var difficulty: Int
    public var minAge: Int?
    public var region: String?

    public init(
        id: String,
        topic: String,
        ageBand: AgeBand,
        type: QuestionType,
        question: String,
        options: [String]? = nil,
        answer: String?,
        acceptedAnswers: [String] = [],
        funFact: String? = nil,
        explanation: String? = nil,
        difficulty: Int = 1,
        minAge: Int? = nil,
        region: String? = nil
    ) {
        self.id = id
        self.topic = topic
        self.ageBand = ageBand
        self.type = type
        self.question = question
        self.options = options
        self.answer = answer
        self.acceptedAnswers = acceptedAnswers
        self.funFact = funFact
        self.explanation = explanation
        self.difficulty = difficulty
        self.minAge = minAge
        self.region = region
    }

    private enum CodingKeys: String, CodingKey {
        case id, topic, ageBand, type, question, options, answer, acceptedAnswers
        case funFact, explanation, difficulty, minAge, region
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        topic = try c.decode(String.self, forKey: .topic)
        ageBand = try c.decode(AgeBand.self, forKey: .ageBand)
        type = try c.decode(QuestionType.self, forKey: .type)
        question = try c.decode(String.self, forKey: .question)
        options = try c.decodeIfPresent([String].self, forKey: .options)
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        acceptedAnswers = try c.decodeIfPresent([String].self, forKey: .acceptedAnswers) ?? []
        funFact = try c.decodeIfPresent(String.self, forKey: .funFact)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        difficulty = try c.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1
        minAge = try c.decodeIfPresent(Int.self, forKey: .minAge)
        region = try c.decodeIfPresent(String.self, forKey: .region)
    }

    /// The options a player chooses between, in content order.
    /// True/false questions get implicit ["True", "False"] options.
    public var choiceOptions: [String]? {
        if type == .trueFalse { return options ?? ["True", "False"] }
        return type.hasOptions ? options : nil
    }

    /// The sentence read after the answer: `explanation` wins over `funFact`.
    public var followUp: String? { explanation ?? funFact }
}
