/// How a question is asked and judged (FEATURES §4.1).
public enum QuestionType: String, Codable, CaseIterable, Sendable, Hashable {
    /// Free spoken answer, matched against `answer` + `acceptedAnswers`.
    case open
    /// 3–4 options, one correct.
    case multipleChoice
    /// Answer is "True" or "False".
    case trueFalse
    /// A short social situation with spoken options. Scored like multiple choice.
    case scenario
    /// Open discussion prompt. Never scored.
    case talkAbout

    /// Whether answering this question can earn points.
    public var isScored: Bool { self != .talkAbout }

    /// Whether the question is answered by choosing among options.
    public var hasOptions: Bool {
        switch self {
        case .multipleChoice, .scenario, .trueFalse: true
        case .open, .talkAbout: false
        }
    }
}
