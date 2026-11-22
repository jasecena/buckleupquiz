/// One thing the audio layer does while playing a question.
public enum SpeechStep: Hashable, Sendable {
    public enum Purpose: String, Sendable, Hashable {
        case number, question, options, answer, followUp
        /// Between questions ("Thinking caps on!"), or "Once more…" before a repeat.
        case filler
    }

    public enum Cue: String, Sendable, Hashable {
        /// Soft tick while the kids think.
        case think
        /// "I'm listening" chime before the mic opens (voice mode).
        case listening
        /// A short tune between questions (`TurnVariety`).
        case jingle
    }

    case say(String, Purpose)
    case cue(Cue)
    /// Think time, shown as a countdown ring.
    case think(seconds: Double)
    /// Voice answers (ADR-0018): read the `options`, then listen straight away for up to
    /// `seconds` of think time (no beep).
    case listen(seconds: Double, options: String? = nil)
    /// Voice answers: a cheer when right ("Correct! Awesome!"), otherwise just the answer.
    case feedback
    /// Talk About time. Ends when the family says they're done (We're done / Next on
    /// screen, or the car's next-track button), or when the Parent mode timer runs out.
    /// `seconds == nil` means no time limit.
    case discuss(seconds: Double?)
    case wait(seconds: Double)
}

/// User-adjustable timing and reading options (FEATURES §2.2, §2.5).
public struct ListenSettings: Hashable, Sendable, Codable {
    public static let thinkTimeRange: ClosedRange<Double> = 3...20

    /// Think time for quiz questions (and how long the app listens for an answer).
    public var thinkTime: Double = 6
    /// Parent mode's own timer for Talk About prompts. nil = no limit. Defaults to 30 s so
    /// nobody waits forever if Talk About is turned on without looking at the timer.
    public var talkTime: Double? = 30
    public static let talkTimePresets: [Double?] = [nil, 30, 60, 120, 180, 300]
    public var funFacts = true
    public var pauseAfterAnswer: Double = 2

    public init() {}

    // Decoded key by key so settings saved by older builds (missing or extra keys) still load.
    private enum CodingKeys: String, CodingKey { case thinkTime, talkTime, funFacts, pauseAfterAnswer }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ListenSettings()
        thinkTime = try c.decodeIfPresent(Double.self, forKey: .thinkTime) ?? d.thinkTime
        // 0 is a saved "No limit"; a missing key means never chosen, so the default applies.
        let savedTalkTime = try c.decodeIfPresent(Double.self, forKey: .talkTime)
        talkTime = savedTalkTime.map { $0 > 0 ? $0 : nil } ?? d.talkTime
        funFacts = try c.decodeIfPresent(Bool.self, forKey: .funFacts) ?? d.funFacts
        pauseAfterAnswer = try c.decodeIfPresent(Double.self, forKey: .pauseAfterAnswer) ?? d.pauseAfterAnswer
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(thinkTime, forKey: .thinkTime)
        try c.encode(talkTime ?? 0, forKey: .talkTime)
        try c.encode(funFacts, forKey: .funFacts)
        try c.encode(pauseAfterAnswer, forKey: .pauseAfterAnswer)
    }
}

/// Turns a `Turn` into the ordered steps of Listen mode (FEATURES §2.2):
/// read question + options, think, reveal answer (+ fun fact), pause.
public enum ListenScript {
    /// How long the jingle plays (the cue player's tune is this long).
    public static let jingleLength = 1.2

    public static func steps(
        for turn: Turn, category: Topic.Category?, settings: ListenSettings, addressPlayer: Bool,
        firstTurnForPlayer: Bool = true, voiceAnswers: Bool = false, variety: TurnVariety = .none
    ) -> [SpeechStep] {
        let presented = turn.presented
        let q = presented.question
        var steps: [SpeechStep] = []
        switch variety.breather {
        case .silence(let seconds): steps.append(.wait(seconds: seconds))
        case .phrase(let text): steps.append(.say(text, .filler))
        case .jingle: steps += [.cue(.jingle), .wait(seconds: jingleLength)]
        case nil: break
        }
        steps.append(.say(Phrases.questionNumber(turn.number), .number))
        switch turn.kind {
        case .ownReview: steps.append(.say(Phrases.ownReviewIntro, .number))
        case .sharedReview: steps.append(.say(Phrases.sharedReviewIntro, .number))
        case .new: break
        }
        // "Mia, this one's for you!" on a player's first turn, then just "Mia." and a pause.
        if addressPlayer, !turn.player.name.isEmpty {
            if firstTurnForPlayer {
                steps.append(.say(Phrases.forYou(turn.player), .number))
            } else {
                steps.append(.say(Phrases.turnName(turn.player), .number))
                steps.append(.wait(seconds: Phrases.pauseAfterName))
            }
        }
        steps.append(.say(q.question, .question))
        if variety.repeatsQuestion {
            steps.append(.say(Phrases.onceMore, .filler))
            steps.append(.say(q.question, .filler))
        }
        // Every question is a choice, so the options are always read (ADR-0015). With voice
        // answers they're read by the listening step, which opens the mic as soon as they end.
        let options = Phrases.options(presented)
        if let options, !(voiceAnswers && q.type != .talkAbout) {
            steps.append(.say(options, .options))
        }

        if q.type == .talkAbout {
            // Parent mode has its own timer, off by default, so nobody is rushed.
            steps.append(.say(Phrases.talkItOver, .options))
            steps.append(.discuss(seconds: settings.talkTime.map { max($0, 10) }))
            steps.append(.say(Phrases.greatChat, .answer))
        } else {
            let thinkTime = settings.thinkTime.clamped(to: ListenSettings.thinkTimeRange)
            if voiceAnswers {
                // The player answers out loud; the app says whether it was right.
                steps.append(.listen(seconds: thinkTime, options: options))
                steps.append(.feedback)
            } else {
                steps.append(.cue(.think))
                steps.append(.think(seconds: thinkTime))
                steps.append(.say(Phrases.answerReveal(presented, category: category), .answer))
            }
            // Explanations teach the "why" of values questions, so they are always read.
            if let explanation = q.explanation {
                steps.append(.say(explanation, .followUp))
            } else if settings.funFacts, let fact = q.funFact {
                steps.append(.say(fact, .followUp))
            }
        }
        steps.append(.wait(seconds: settings.pauseAfterAnswer))
        return steps
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
