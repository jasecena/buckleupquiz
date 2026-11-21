/// How long a session runs (FEATURES §2.2): a number of questions **for each player**, so
/// everyone gets the same number. A game is at most `maxQuestions` in total (product decision,
/// 2026-11-22: no Endless mode).
public enum SessionLength: Hashable, Codable, Sendable {
    case questions(Int)

    public static let presets: [SessionLength] = [.questions(5), .questions(10), .questions(15)]
    /// The fewest questions each that makes a proper game.
    public static let minimumEach = 5
    /// The most questions in one game, all players together.
    public static let maxQuestions = 50

    /// Questions for each player.
    public var perPlayer: Int {
        switch self { case .questions(let n): n }
    }

    /// Questions each for this many players, keeping the game within `maxQuestions`.
    public func each(players: Int) -> Int {
        max(1, min(perPlayer, Self.maxQuestions / max(1, players)))
    }

    public var displayName: String { "\(perPlayer) questions each" }
}

public struct SessionConfig: Sendable, Hashable {
    public var topics: [String]
    /// Players in turn order. Listen mode uses `[Player.listener(ageBand:)]`.
    public var players: [Player]
    public var length: SessionLength
    public var includeTalkAbout: Bool
    public var shuffleOptions: Bool
    public var rules: ScoringRules

    public init(
        topics: [String], players: [Player], length: SessionLength = .questions(10),
        includeTalkAbout: Bool = true, shuffleOptions: Bool = true, rules: ScoringRules = ScoringRules()
    ) {
        precondition(!players.isEmpty, "A session needs at least one player")
        self.topics = topics
        self.players = players
        self.length = length
        self.includeTalkAbout = includeTalkAbout
        self.shuffleOptions = shuffleOptions
        self.rules = rules
    }

    /// True when turns are addressed to named players ("Mia, this one's for you").
    public var isTurnBased: Bool { players.count > 1 || players.contains { !$0.name.isEmpty } }
}

/// One question for one player.
public struct Turn: Hashable, Sendable {
    /// 1-based question number in the session.
    public let number: Int
    public let player: Player
    public let presented: PresentedQuestion
    /// New question, or a review (ADR-0016).
    public let kind: TurnKind

    public init(number: Int, player: Player, presented: PresentedQuestion, kind: TurnKind = .new) {
        self.number = number
        self.player = player
        self.presented = presented
        self.kind = kind
    }
}

/// The game state for one session: the planned turns, scoring and each player's Leitner boxes
/// (ADR-0016). A value type with no I/O; the app persists `learning` afterwards.
///
/// **Every turn is planned before the game starts** (product decision, 2026-11-22), so the
/// app knows up front how many questions each player gets and can say so ("out of questions
/// for today") before anyone starts. Turns go round the players in order, and every player gets
/// the same number: if someone would run short, the last, incomplete round is dropped.
public struct QuizSession: Sendable {
    /// One planned turn.
    public struct PlannedTurn: Sendable, Hashable {
        public let player: Player
        public let question: Question
        public let kind: TurnKind
        public let cost: FreshBudget.Source
    }

    public let config: SessionConfig
    public private(set) var currentTurn: Turn?
    public private(set) var turnsPlayed = 0
    public private(set) var isFinished = false
    public private(set) var scores: ScoreKeeper
    /// Leitner boxes for the whole family, keyed by player id, updated as turns end. Absent
    /// family members are included so their recent questions can be shared and nobody gets a
    /// question twice in a day. Persist after the session.
    public private(set) var learning: [String: LearningRecord]
    /// `LearningDay` number for today.
    public let day: Int
    /// How the current turn went, committed to `learning` when the turn ends.
    /// nil means unanswered (e.g. skipped before the answer), which leaves the boxes alone.
    public private(set) var currentResult: ReviewResult?

    /// Every turn of the game, in order.
    public let plan: [PlannedTurn]
    /// Questions each player asked for, and how many each will actually get.
    public let requestedEach: Int
    public let plannedEach: Int
    /// What's left of the budget after planning (for replacing a skipped question).
    public private(set) var budget: FreshBudget
    /// What each question asked so far cost, by question id (the app charges these afterwards).
    public private(set) var asked: [String: FreshBudget.Source] = [:]

    private var selector: QuestionSelector
    private var turnsTaken: [String: Int] = [:]
    private var rng: AnyRandomGenerator
    private var nextIndex = 0
    private var recordedCurrent = false

    public init(
        bank: QuestionBank, config: SessionConfig,
        learning: [String: LearningRecord] = [:], day: Int = LearningDay.number(),
        budget: FreshBudget = .unlimited, rng: AnyRandomGenerator = .system()
    ) {
        self.config = config
        self.scores = ScoreKeeper(rules: config.rules)
        self.learning = learning
        self.day = day
        var rng = rng
        var selector = QuestionSelector(bank: bank, topics: config.topics, includeTalkAbout: config.includeTalkAbout)
        var budget = budget
        // Anything the family has already had is theirs: never charged again.
        for record in learning.values { budget.unlocked.formUnion(record.cards.keys) }

        let requested = config.length.each(players: config.players.count)
        var kinds: [String: [TurnKind]] = [:]
        for player in config.players { kinds[player.id] = ReviewMix.plan(turns: requested, using: &rng) }

        var plan: [PlannedTurn] = []
        rounds: for round in 0..<requested {
            let before = (selector, budget)
            var turns: [PlannedTurn] = []
            for player in config.players {
                guard let pick = selector.next(for: player, kind: kinds[player.id]![round], family: learning,
                                               day: day, budget: &budget, using: &rng) else {
                    // Someone has nothing left: drop this round so everyone stays equal.
                    (selector, budget) = before
                    break rounds
                }
                turns.append(PlannedTurn(player: player, question: pick.question, kind: pick.kind, cost: pick.cost))
            }
            plan += turns
        }
        self.rng = rng
        self.selector = selector
        self.budget = budget
        self.plan = plan
        self.requestedEach = requested
        self.plannedEach = plan.count / max(1, config.players.count)
    }

    /// Moves to the next planned turn. Returns nil (and finishes) when the plan is done.
    /// An unrecorded current turn counts as skipped.
    ///
    /// `samePlayer`: the current question was skipped before it was answered, so it's still
    /// the same player's turn: they get another question with the same number, if there is one
    /// to spare. If not, play carries on with the plan.
    @discardableResult
    public mutating func advance(samePlayer: Bool = false) -> Turn? {
        guard !isFinished else { return nil }
        let replaced = samePlayer ? currentTurn : nil
        if currentTurn != nil, !recordedCurrent { record(.skipped) }
        commitCurrent()
        if let replaced,
           let pick = selector.next(for: replaced.player, kind: .new, family: learning, day: day,
                                    budget: &budget, using: &rng) {
            return begin(PlannedTurn(player: replaced.player, question: pick.question, kind: pick.kind, cost: pick.cost),
                         number: replaced.number)
        }
        guard nextIndex < plan.count else { return finish() }
        let planned = plan[nextIndex]
        nextIndex += 1
        turnsTaken[planned.player.id, default: 0] += 1
        return begin(planned, number: nextIndex)
    }

    private mutating func begin(_ planned: PlannedTurn, number: Int) -> Turn {
        let question = planned.question
        turnsPlayed = number
        asked[question.id] = asked[question.id] ?? planned.cost
        if question.type == .talkAbout {
            learning[planned.player.id, default: LearningRecord()].noteTalkedAbout(question.id)
        }
        let presented = PresentedQuestion(question: question, shuffleOptions: config.shuffleOptions, using: &rng)
        let turn = Turn(number: number, player: planned.player, presented: presented, kind: planned.kind)
        currentTurn = turn
        currentResult = nil
        recordedCurrent = false
        return turn
    }

    /// How many asked questions were paid from each source (the app charges `.shared` to packs
    /// or the subscription's daily allowance).
    public var charges: [FreshBudget.Source: Int] {
        asked.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Records the outcome of the current turn. Talk About prompts are always `notScored`.
    @discardableResult
    public mutating func record(_ outcome: AnswerOutcome) -> ScoreEvent? {
        guard let turn = currentTurn, !recordedCurrent else { return nil }
        recordedCurrent = true
        switch outcome {
        case .correct: currentResult = .correct
        case .incorrect, .timedOut: currentResult = .incorrect
        // Not heard: unless we caught a wrong answer, they heard the question and the answer, so
        // it counts as remembered and moves forward (product decision, 2026-11-22). No points.
        case .unheard: currentResult = .heard
        case .skipped: currentResult = nil
        case .notScored: break
        }
        let effective = turn.presented.question.type.isScored ? outcome : .notScored
        return scores.record(effective, playerID: turn.player.id, topic: turn.presented.question.topic)
    }

    /// Sets how the current turn went for its player's Leitner boxes, e.g. a parent tapping
    /// "Got it" / "Not yet". Can be changed until the turn ends. Ignored for Talk About.
    public mutating func mark(_ result: ReviewResult?) {
        guard let turn = currentTurn, turn.presented.question.type.isScored else { return }
        currentResult = result
    }

    /// Ends the session early (e.g. "stop").
    public mutating func stop() { _ = finish() }

    /// Questions in this game (everyone gets `plannedEach`).
    public var questionLimit: Int? { plan.count }

    /// Questions this player has been asked so far (skipped ones don't count).
    public func turns(for playerID: String) -> Int { turnsTaken[playerID] ?? 0 }

    /// The most points a player could have from their turns (every answer right, streak bonuses
    /// included): the upper bound for a grown-up's score correction.
    public func maxPoints(for playerID: String) -> Int {
        let turns = turns(for: playerID)
        guard turns > 0 else { return 0 }
        return (1...turns).reduce(0) { $0 + config.rules.points(forStreak: $1) }
    }

    /// A grown-up fixes a score after the game, within 0...maxPoints.
    public mutating func setPoints(_ points: Int, for playerID: String) {
        scores.setPoints(min(max(0, points), maxPoints(for: playerID)), for: playerID)
    }

    /// True once the current turn's outcome has been recorded.
    public var isCurrentRecorded: Bool { currentTurn == nil || recordedCurrent }

    public var scoreboard: [ScoreboardEntry] { Scoreboard.rank(players: config.players, scores: scores) }

    /// Updates the boxes when a turn ends (ADR-0016). The player whose turn it was moves up
    /// (right) or starts over (wrong). Everyone else playing who could get this question heard
    /// it too: they move up when the answer was right, and are left alone when it was wrong.
    private mutating func commitCurrent() {
        guard let turn = currentTurn, turn.presented.question.type.isScored, let result = currentResult else { return }
        let question = turn.presented.question
        learning[turn.player.id, default: LearningRecord()].record(result, for: question.id, on: day)
        if result != .incorrect {
            for other in config.players where other.id != turn.player.id && QuestionSelector.suits(question, other) {
                learning[other.id, default: LearningRecord()].record(.heard, for: question.id, on: day)
            }
        }
        currentResult = nil
    }

    private mutating func finish() -> Turn? {
        commitCurrent()
        isFinished = true
        currentTurn = nil
        return nil
    }
}
