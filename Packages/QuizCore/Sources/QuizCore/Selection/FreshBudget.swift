/// How many questions the family may hear for the first time (ADR-0022).
///
/// A question costs one, once: the first time anyone in the family is asked it. Reviews,
/// repeats and anything the family has already had are always free, and so are Talk About
/// prompts. The app builds this before each game from the family's plan (free allowance,
/// question packs, subscription) and charges what was actually asked afterwards.
public struct FreshBudget: Sendable, Hashable {
    /// Where a question's cost came from.
    public enum Source: String, Sendable, Hashable, Codable {
        /// Already unlocked (or a Talk About prompt): no cost.
        case free
        /// The topic's own allowance (free tier: starter questions plus the daily top-up).
        case topic
        /// The shared pool (question packs, or a subscription's daily allowance).
        case shared
    }

    /// New questions allowed per topic.
    public var perTopic: [String: Int]
    /// New questions allowed in any topic. `Int.max` means unlimited.
    public var shared: Int
    /// Question ids the family already has: never charged again.
    public var unlocked: Set<String>

    public init(perTopic: [String: Int] = [:], shared: Int = 0, unlocked: Set<String> = []) {
        self.perTopic = perTopic
        self.shared = shared
        self.unlocked = unlocked
    }

    /// No limits (tests, previews, and builds without metering).
    public static let unlimited = FreshBudget(shared: .max)

    public func canAfford(_ question: Question) -> Bool {
        question.type == .talkAbout || unlocked.contains(question.id)
            || (perTopic[question.topic] ?? 0) > 0 || shared > 0
    }

    /// Pays for a question about to be asked. nil if it can't be afforded.
    public mutating func spend(_ question: Question) -> Source? {
        if question.type == .talkAbout || unlocked.contains(question.id) { return .free }
        if let left = perTopic[question.topic], left > 0 {
            perTopic[question.topic] = left - 1
            unlocked.insert(question.id)
            return .topic
        }
        if shared > 0 {
            if shared != .max { shared -= 1 }
            unlocked.insert(question.id)
            return .shared
        }
        return nil
    }
}
