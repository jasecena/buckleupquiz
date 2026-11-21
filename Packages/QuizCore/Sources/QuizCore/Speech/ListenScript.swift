/// One thing the audio layer does while playing a question.
public enum SpeechStep: Hashable, Sendable {
    public enum Purpose: String, Sendable, Hashable {
        case number, question, options, answer, followUp
    }

    public enum Cue: String, Sendable, Hashable {
        /// Soft tick while the kids think.
        case think
        /// "I'm listening" chime before the mic opens (voice mode).
        case listening
    }

    case say(String, Purpose)
    case cue(Cue)
    /// Think time, shown as a countdown ring.
    case think(seconds: Double)
    case wait(seconds: Double)
}

/// User-adjustable timing and reading options (FEATURES §2.2, §2.5).
public struct ListenSettings: Hashable, Sendable, Codable {
    public static let thinkTimeRange: ClosedRange<Double> = 3...20

    public var thinkTime: Double = 8
    public var talkAboutThinkTime: Double = 30
    public var readOptions = true
    public var funFacts = true
    public var pauseAfterAnswer: Double = 2

    public init() {}
}

/// Turns a `Turn` into the ordered steps of Listen mode (FEATURES §2.2):
/// read question (+ options), think, reveal answer (+ fun fact), pause.
public enum ListenScript {
    public static func steps(
        for turn: Turn, category: Topic.Category?, settings: ListenSettings, addressPlayer: Bool
    ) -> [SpeechStep] {
        let presented = turn.presented
        let q = presented.question
        var steps: [SpeechStep] = [
            .say(Phrases.questionNumber(turn.number), .number),
            .say(Phrases.addressed(q.question, to: addressPlayer ? turn.player : nil), .question),
        ]
        if settings.readOptions, let options = Phrases.options(presented) {
            steps.append(.say(options, .options))
        }
        steps.append(.cue(.think))

        if q.type == .talkAbout {
            steps.append(.think(seconds: settings.talkAboutThinkTime))
            steps.append(.say(Phrases.greatChat, .answer))
        } else {
            steps.append(.think(seconds: settings.thinkTime.clamped(to: ListenSettings.thinkTimeRange)))
            steps.append(.say(Phrases.answerReveal(presented, category: category), .answer))
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
