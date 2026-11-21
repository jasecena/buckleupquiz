/// Picks the next question for a player (FEATURES §4.4, ADR-0016):
///
/// 1. questions due for review in their Leitner boxes (lowest box first),
/// 2. then questions they have never had (preferring ones nobody else got this session),
/// 3. then, in Parent mode, Talk About prompts they've already discussed.
///
/// A player is asked each question at most once per session. Different players may get
/// the same question, because each player has their own boxes. Questions that aren't due
/// yet, or are already learned, are left alone.
public struct QuestionSelector: Sendable {
    public let bank: QuestionBank
    public let topics: [String]
    public let includeTalkAbout: Bool
    /// Question ids asked this session, per player id.
    public private(set) var askedThisSession: [String: Set<String>] = [:]
    private var askedToAnyone: Set<String> = []

    public init(bank: QuestionBank, topics: [String], includeTalkAbout: Bool) {
        self.bank = bank
        self.topics = topics
        self.includeTalkAbout = includeTalkAbout
    }

    /// Questions `player` could still be asked this session, before looking at their boxes.
    public func pool(for player: Player) -> [Question] {
        let asked = askedThisSession[player.id] ?? []
        return bank.questions(topics: topics, ageBand: player.ageBand).filter { q in
            !asked.contains(q.id)
                && (includeTalkAbout || q.type != .talkAbout)
                && (q.minAge == nil || player.age == nil || player.age! >= q.minAge!)
        }
    }

    /// How many questions `player` can be asked today: due reviews, new questions and
    /// (in Parent mode) Talk About prompts.
    public func availableCount(for player: Player, record: LearningRecord, day: Int) -> Int {
        pool(for: player).filter { q in
            q.type == .talkAbout || record.isNew(q.id) || record.isDue(q.id, on: day)
        }.count
    }

    public mutating func next(
        for player: Player, record: LearningRecord, day: Int, using rng: inout some RandomNumberGenerator
    ) -> Question? {
        let pool = pool(for: player).shuffled(using: &rng)

        let due = pool.filter { $0.type != .talkAbout && record.isDue($0.id, on: day) }
        let fresh = pool.filter { q in
            q.type == .talkAbout ? !record.talkedAbout.contains(q.id) : record.isNew(q.id)
        }
        let freshForEveryone = fresh.filter { !askedToAnyone.contains($0.id) }
        let talkAgain = pool.filter { $0.type == .talkAbout }

        let pick = due.min { a, b in
            let (ca, cb) = (record.card(a.id)!, record.card(b.id)!)
            return (ca.box, ca.due) < (cb.box, cb.due)
        } ?? freshForEveryone.first ?? fresh.first ?? talkAgain.first

        guard let pick else { return nil }
        askedThisSession[player.id, default: []].insert(pick.id)
        askedToAnyone.insert(pick.id)
        return pick
    }
}
