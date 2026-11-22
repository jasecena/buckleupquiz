/// A little variety so a game feels like a person reading it, not a machine (product decision,
/// 2026-11-22): something different between questions, and some long or hard questions read
/// twice. Chosen at random per turn, so a seeded generator gives repeatable tests.
public struct TurnVariety: Hashable, Sendable {
    /// Before the question number. Never before the first question, and never after the last
    /// one (it belongs to the next turn), so the outro comes straight after the final answer.
    public var breather: Breather?
    /// Read the question a second time ("Once more…") before the options.
    public var repeatsQuestion: Bool

    public init(breather: Breather? = nil, repeatsQuestion: Bool = false) {
        self.breather = breather
        self.repeatsQuestion = repeatsQuestion
    }

    /// No variety: the plain script.
    public static let none = TurnVariety()

    public enum Breather: Hashable, Sendable {
        /// A moment of quiet.
        case silence(seconds: Double)
        /// "Okay, here comes the next one…"
        case phrase(String)
        /// A short tune.
        case jingle
    }

    /// Questions this long (in words) or this hard may be read twice.
    public static let longQuestionWords = 12
    public static let hardDifficulty = 3
    /// How often a long or hard question is read twice.
    public static let repeatChance = 0.4

    public static func isLongOrHard(_ question: Question) -> Bool {
        question.type != .talkAbout
            && (question.question.split(separator: " ").count >= longQuestionWords
                || question.difficulty >= hardDifficulty)
    }

    /// The variety for one turn. `firstQuestion`: the game is just starting, so no breather.
    public static func random(for turn: Turn, firstQuestion: Bool,
                              using rng: inout some RandomNumberGenerator) -> TurnVariety {
        var variety = TurnVariety()
        if !firstQuestion {
            switch Double.random(in: 0..<1, using: &rng) {
            case ..<0.4: variety.breather = .silence(seconds: (Double.random(in: 1...2, using: &rng) * 10).rounded() / 10)
            case ..<0.75: variety.breather = .phrase(Phrases.betweenQuestions.randomElement(using: &rng)!)
            default: variety.breather = .jingle
            }
        }
        if isLongOrHard(turn.presented.question) {
            variety.repeatsQuestion = Double.random(in: 0..<1, using: &rng) < repeatChance
        }
        return variety
    }
}
