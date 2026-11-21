/// How a question is asked and judged (FEATURES §4.1, ADR-0015).
/// Every scored question is a single choice between options; there are no free-answer questions.
public enum QuestionType: String, Codable, CaseIterable, Sendable, Hashable {
    /// 3–4 options, one correct.
    case multipleChoice
    /// Answer is "True" or "False".
    case trueFalse
    /// A short social situation with spoken options. Scored like multiple choice.
    case scenario
    /// Open discussion prompt. Never scored, no options.
    case talkAbout

    /// Whether answering this question can earn points.
    public var isScored: Bool { self != .talkAbout }

    /// Whether the question is answered by choosing among options.
    public var hasOptions: Bool { self != .talkAbout }
}
