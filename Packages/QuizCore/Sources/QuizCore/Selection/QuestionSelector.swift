/// Picks the next question for a player (FEATURES §4.4):
/// never repeats within a session, prefers questions the player hasn't seen before.
public struct QuestionSelector: Sendable {
    public let bank: QuestionBank
    public let topics: [String]
    public let includeTalkAbout: Bool
    public private(set) var askedThisSession: Set<String> = []

    public init(bank: QuestionBank, topics: [String], includeTalkAbout: Bool) {
        self.bank = bank
        self.topics = topics
        self.includeTalkAbout = includeTalkAbout
    }

    /// Questions still available to `player` this session.
    public func pool(for player: Player) -> [Question] {
        bank.questions(topics: topics, ageBand: player.ageBand).filter { q in
            !askedThisSession.contains(q.id)
                && (includeTalkAbout || q.type != .talkAbout)
                && (q.minAge == nil || player.age == nil || player.age! >= q.minAge!)
        }
    }

    public mutating func next(
        for player: Player, seen: Set<String>, using rng: inout some RandomNumberGenerator
    ) -> Question? {
        let pool = pool(for: player)
        let unseen = pool.filter { !seen.contains($0.id) }
        guard let pick = (unseen.isEmpty ? pool : unseen).randomElement(using: &rng) else { return nil }
        askedThisSession.insert(pick.id)
        return pick
    }
}
