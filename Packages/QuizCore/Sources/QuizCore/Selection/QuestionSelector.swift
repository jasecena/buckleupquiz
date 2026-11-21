/// Picks the next question for a player (FEATURES §4.4, ADR-0016).
///
/// - No question is played twice on the same day, for anyone in the family.
/// - Each turn has a `TurnKind` from `ReviewMix`: new (most turns), the player's own due
///   reviews, or questions another family member had recently. If that kind has nothing
///   left, it falls back to the others, so sessions don't stall.
/// - New questions nobody in the family has had come first, so siblings hear different things.
/// - Questions that aren't due yet, or are learned, are left alone.
public struct QuestionSelector: Sendable {
    public let bank: QuestionBank
    public let topics: [String]
    public let includeTalkAbout: Bool
    /// Question ids asked to anyone this session.
    public private(set) var askedThisSession: Set<String> = []

    public init(bank: QuestionBank, topics: [String], includeTalkAbout: Bool) {
        self.bank = bank
        self.topics = topics
        self.includeTalkAbout = includeTalkAbout
    }

    /// Questions in `player`'s band and age not yet asked this session (before the boxes).
    /// If the topics have nothing at all for the player's band, the nearest band's questions are
    /// used instead (younger first), so every child can play every topic.
    public func pool(for player: Player) -> [Question] {
        let band = contentBand(for: player)
        return bank.questions(topics: topics, ageBand: band).filter { q in
            !askedThisSession.contains(q.id)
                && (includeTalkAbout || q.type != .talkAbout)
                && Self.ageAllows(q, player)
        }
    }

    /// The player's own band, or the nearest one with content in these topics.
    public func contentBand(for player: Player) -> AgeBand {
        let order = AgeBand.allCases.sorted { a, b in
            func rank(_ band: AgeBand) -> (Int, Int) {
                band == player.ageBand ? (0, 0) : band < player.ageBand ? (1, -band.index) : (2, band.index)
            }
            return rank(a) < rank(b)
        }
        return order.first { !bank.questions(topics: topics, ageBand: $0).isEmpty } ?? player.ageBand
    }

    static func ageAllows(_ q: Question, _ player: Player) -> Bool {
        q.minAge == nil || player.age == nil || player.age! >= q.minAge!
    }

    static func suits(_ q: Question, _ player: Player) -> Bool {
        q.ageBand == player.ageBand && ageAllows(q, player)
    }

    /// How many questions `player` could still get today.
    public func availableCount(for player: Player, family: [String: LearningRecord], day: Int) -> Int {
        let c = candidates(for: player, family: family, day: day)
        return Set((c.own + c.shared + c.fresh + c.talkAgain).map(\.id)).count
    }

    /// A chosen question, the kind of turn it turned out to be, and what it cost.
    public struct Pick: Sendable {
        public let question: Question
        public let kind: TurnKind
        public let cost: FreshBudget.Source
    }

    /// The next question for `player`, paid for from `budget` if it's new to the family.
    /// nil when nothing fresh, due or affordable is left.
    public mutating func next(
        for player: Player, kind: TurnKind, family: [String: LearningRecord], day: Int,
        budget: inout FreshBudget, using rng: inout some RandomNumberGenerator
    ) -> Pick? {
        var c = candidates(for: player, family: family, day: day)
        let affordable = budget
        c.freshForFamily = c.freshForFamily.filter(affordable.canAfford)
        c.fresh = c.fresh.filter(affordable.canAfford)
        let order: [(TurnKind, [Question])] = switch kind {
        case .ownReview: [(.ownReview, c.own), (.sharedReview, c.shared), (.new, c.freshForFamily), (.new, c.fresh)]
        case .sharedReview: [(.sharedReview, c.shared), (.ownReview, c.own), (.new, c.freshForFamily), (.new, c.fresh)]
        case .new: [(.new, c.freshForFamily), (.new, c.fresh), (.ownReview, c.own), (.sharedReview, c.shared),
                    (.new, c.talkAgain)]
        }
        guard let (actual, list) = order.first(where: { !$0.1.isEmpty }),
              let pick = list.randomElement(using: &rng),
              let cost = budget.spend(pick) else { return nil }
        askedThisSession.insert(pick.id)
        return Pick(question: pick, kind: actual, cost: cost)
    }

    struct Candidates {
        var own: [Question] = []
        /// Only the most recent day's shared questions ("from yesterday" first).
        var shared: [Question] = []
        var freshForFamily: [Question] = []
        var fresh: [Question] = []
        var talkAgain: [Question] = []
    }

    func candidates(for player: Player, family: [String: LearningRecord], day: Int) -> Candidates {
        let mine = family[player.id] ?? LearningRecord()
        let others = family.filter { $0.key != player.id }.map(\.value)
        var c = Candidates()
        var sharedByDay: [Int: [Question]] = [:]
        for q in pool(for: player) where !family.values.contains(where: { $0.wasPlayed(q.id, on: day) }) {
            if q.type == .talkAbout {
                if mine.talkedAbout.contains(q.id) {
                    c.talkAgain.append(q)
                } else {
                    c.fresh.append(q)
                    if !others.contains(where: { $0.talkedAbout.contains(q.id) }) { c.freshForFamily.append(q) }
                }
                continue
            }
            if mine.isLearned(q.id) { continue }
            if mine.isDue(q.id, on: day) { c.own.append(q) }
            if mine.isNew(q.id) {
                c.fresh.append(q)
                if others.allSatisfy({ $0.isNew(q.id) }) { c.freshForFamily.append(q) }
            }
            if mine.isNew(q.id) || mine.isDue(q.id, on: day) {
                let recent = others.compactMap { $0.card(q.id)?.last }
                    .filter { $0 < day && $0 >= day - ReviewMix.sharedLookback }.max()
                if let recent { sharedByDay[recent, default: []].append(q) }
            }
        }
        if let latest = sharedByDay.keys.max() { c.shared = sharedByDay[latest] ?? [] }
        return c
    }
}
