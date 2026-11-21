/// How long a session runs (FEATURES §2.2).
public enum SessionLength: Hashable, Codable, Sendable {
    case questions(Int)
    /// Paid tier only. Runs until the question pool is exhausted or the player stops.
    case endless

    public static let presets: [SessionLength] = [.questions(10), .questions(20), .questions(30), .endless]

    public var limit: Int? {
        if case .questions(let n) = self { return n }
        return nil
    }

    public var displayName: String {
        switch self {
        case .questions(let n): "\(n) questions"
        case .endless: "Endless"
        }
    }
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

/// The game state for one session: turn rotation, question selection, scoring and each
/// player's Leitner boxes (ADR-0016). A value type with no I/O; the app persists `learning`
/// afterwards.
public struct QuizSession: Sendable {
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

    private var selector: QuestionSelector
    /// Each player's own turn plan (`ReviewMix`), so everyone gets their share of new questions.
    private var plans: [String: [TurnKind]] = [:]
    private var turnsTaken: [String: Int] = [:]
    private var rng: AnyRandomGenerator
    private var nextPlayerIndex = 0
    private var recordedCurrent = false

    public init(
        bank: QuestionBank, config: SessionConfig,
        learning: [String: LearningRecord] = [:], day: Int = LearningDay.number(),
        rng: AnyRandomGenerator = .system()
    ) {
        self.config = config
        self.selector = QuestionSelector(bank: bank, topics: config.topics, includeTalkAbout: config.includeTalkAbout)
        self.scores = ScoreKeeper(rules: config.rules)
        self.learning = learning
        self.day = day
        self.rng = rng
    }

    /// Moves to the next turn. Returns nil (and finishes) when the length is reached
    /// or no player has questions left. An unrecorded current turn counts as skipped.
    @discardableResult
    public mutating func advance() -> Turn? {
        guard !isFinished else { return nil }
        if currentTurn != nil, !recordedCurrent { record(.skipped) }
        commitCurrent()
        if let limit = config.length.limit, turnsPlayed >= limit { return finish() }

        // Rotate through players, skipping anyone whose pool is empty.
        for offset in 0..<config.players.count {
            let index = (nextPlayerIndex + offset) % config.players.count
            let player = config.players[index]
            let taken = turnsTaken[player.id] ?? 0
            while (plans[player.id]?.count ?? 0) <= taken {
                plans[player.id, default: []] += ReviewMix.plan(turns: turnsPerPlayer, using: &rng)
            }
            guard let (question, kind) = selector.next(
                for: player, kind: plans[player.id]![taken], family: learning, day: day, using: &rng) else { continue }
            turnsTaken[player.id] = taken + 1
            nextPlayerIndex = (index + 1) % config.players.count
            turnsPlayed += 1
            if question.type == .talkAbout { learning[player.id, default: LearningRecord()].noteTalkedAbout(question.id) }
            let presented = PresentedQuestion(question: question, shuffleOptions: config.shuffleOptions, using: &rng)
            let turn = Turn(number: turnsPlayed, player: player, presented: presented, kind: kind)
            currentTurn = turn
            currentResult = nil
            recordedCurrent = false
            return turn
        }
        return finish()
    }

    /// Records the outcome of the current turn. Talk About prompts are always `notScored`.
    @discardableResult
    public mutating func record(_ outcome: AnswerOutcome) -> ScoreEvent? {
        guard let turn = currentTurn, !recordedCurrent else { return nil }
        recordedCurrent = true
        switch outcome {
        case .correct: currentResult = .correct
        case .incorrect, .timedOut: currentResult = .incorrect
        case .skipped, .unheard: currentResult = nil
        case .notScored: break
        }
        let effective = turn.presented.question.type.isScored ? outcome : .notScored
        return scores.record(effective, playerID: turn.player.id, topic: turn.presented.question.topic)
    }

    /// Turns each player is expected to get, for planning their review share.
    private var turnsPerPlayer: Int {
        let total = config.length.limit ?? ReviewMix.endlessBlock * config.players.count
        return max(1, (total + config.players.count - 1) / config.players.count)
    }

    /// Sets how the current turn went for its player's Leitner boxes, e.g. a parent tapping
    /// "Got it" / "Not yet". Can be changed until the turn ends. Ignored for Talk About.
    public mutating func mark(_ result: ReviewResult?) {
        guard let turn = currentTurn, turn.presented.question.type.isScored else { return }
        currentResult = result
    }

    /// Ends the session early (e.g. "stop").
    public mutating func stop() { _ = finish() }

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
