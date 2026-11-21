/// What happened when a question was played.
public enum AnswerOutcome: String, Codable, Sendable, Hashable {
    case correct
    case incorrect
    /// Nothing heard before think time ran out. Counts as incorrect.
    case timedOut
    /// Skipped by a player or parent. Not counted as attempted, but breaks the streak.
    case skipped
    /// Talk About prompts and Listen mode: no score.
    case notScored
    /// Voice answers: nothing (or only a mumble) was heard. No score, no comment, streak kept.
    /// For the Leitner boxes it counts as remembered (moves forward), like an untapped answer in
    /// Listen mode: only a wrong answer we actually caught starts over (ADR-0016, ADR-0018).
    case unheard
}

/// FEATURES §3.5: +10 per correct, +5 streak bonus from the third correct in a row.
public struct ScoringRules: Sendable, Hashable {
    public var pointsPerCorrect = 10
    public var streakBonus = 5
    /// The streak length at which the bonus starts.
    public var streakBonusFrom = 3

    public init() {}

    public func points(forStreak streak: Int) -> Int {
        pointsPerCorrect + (streak >= streakBonusFrom ? streakBonus : 0)
    }
}

public struct TopicStats: Codable, Hashable, Sendable {
    public var correct = 0
    public var attempted = 0
    public var accuracy: Double { attempted == 0 ? 0 : Double(correct) / Double(attempted) }
    public init(correct: Int = 0, attempted: Int = 0) {
        self.correct = correct
        self.attempted = attempted
    }
}

public struct PlayerStats: Codable, Hashable, Sendable {
    public var points = 0
    public var correct = 0
    public var attempted = 0
    public var currentStreak = 0
    public var bestStreak = 0
    public var byTopic: [String: TopicStats] = [:]

    public init() {}

    public var accuracy: Double { attempted == 0 ? 0 : Double(correct) / Double(attempted) }

    /// Lifetime totals after adding one session's stats.
    public func adding(_ session: PlayerStats) -> PlayerStats {
        var total = self
        total.points += session.points
        total.correct += session.correct
        total.attempted += session.attempted
        total.currentStreak = session.attempted > 0 ? session.currentStreak : currentStreak
        total.bestStreak = max(bestStreak, session.bestStreak)
        for (topic, stats) in session.byTopic {
            total.byTopic[topic, default: TopicStats()].correct += stats.correct
            total.byTopic[topic, default: TopicStats()].attempted += stats.attempted
        }
        return total
    }
}

/// The score change from one answer, used for spoken feedback ("That's three in a row!").
public struct ScoreEvent: Hashable, Sendable {
    public let playerID: String
    public let outcome: AnswerOutcome
    public let pointsAwarded: Int
    public let streak: Int
}

/// Running scores for a session, keyed by player id.
public struct ScoreKeeper: Sendable {
    public let rules: ScoringRules
    public private(set) var stats: [String: PlayerStats] = [:]

    public init(rules: ScoringRules = ScoringRules()) { self.rules = rules }

    public func stats(for playerID: String) -> PlayerStats { stats[playerID] ?? PlayerStats() }

    /// A grown-up's correction after the game ("we missed Mia's answer"). Points only.
    public mutating func setPoints(_ points: Int, for playerID: String) {
        stats[playerID, default: PlayerStats()].points = max(0, points)
    }

    @discardableResult
    public mutating func record(_ outcome: AnswerOutcome, playerID: String, topic: String) -> ScoreEvent {
        var s = stats(for: playerID)
        var awarded = 0
        switch outcome {
        case .correct:
            s.currentStreak += 1
            s.bestStreak = max(s.bestStreak, s.currentStreak)
            awarded = rules.points(forStreak: s.currentStreak)
            s.points += awarded
            s.correct += 1
            s.attempted += 1
            s.byTopic[topic, default: TopicStats()].correct += 1
            s.byTopic[topic, default: TopicStats()].attempted += 1
        case .incorrect, .timedOut:
            s.currentStreak = 0
            s.attempted += 1
            s.byTopic[topic, default: TopicStats()].attempted += 1
        case .skipped:
            s.currentStreak = 0
        case .notScored, .unheard:
            break
        }
        stats[playerID] = s
        return ScoreEvent(playerID: playerID, outcome: outcome, pointsAwarded: awarded, streak: s.currentStreak)
    }
}
