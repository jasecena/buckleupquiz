/// How a question is asked and judged (FEATURES §4.1, ADR-0015).
///
/// Quiz questions are always a single choice: three options, or true/false.
/// Talk About prompts are the open questions: a chat with no right answer.
public enum QuestionType: String, Codable, CaseIterable, Sendable, Hashable {
    /// Exactly three options, one correct. Values and safety topics use it for
    /// everyday situations ("Your friend falls over. What's the kind thing to do?").
    case multipleChoice
    /// Answer is "True" or "False".
    case trueFalse
    /// Open discussion prompt (Parent mode). Never scored, no options, double think time.
    case talkAbout

    /// Whether answering this question can earn points.
    public var isScored: Bool { self != .talkAbout }

    /// Whether the question is answered by choosing among options.
    public var hasOptions: Bool { self != .talkAbout }
}
