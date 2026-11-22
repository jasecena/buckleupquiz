/// What a child's spoken reply means on their turn (FEATURES §3.3, ADR-0018).
/// No speaker identification: whoever's turn it is gets the result.
public enum VoiceReply: Equatable, Sendable {
    /// A game command such as "skip" or "repeat".
    case command(VoiceCommand)
    /// An answer, judged against the question.
    case answer(AnswerOutcome, heard: String)
    /// Something was heard, but it didn't pick an option: "umm", chatter in the car, or the
    /// car speakers' echo of the question. Not an answer, so listening carries on.
    case garbled
    /// Nothing was heard before the listening window closed.
    case silence

    /// True when the reply settles the turn (an answer or a command), so listening can stop.
    /// Anything else keeps listening until the think time is up.
    public var isConclusive: Bool {
        switch self {
        case .command, .answer: true
        case .garbled, .silence: false
        }
    }

    /// Interprets every alternative transcription of one reply. An answer has to name an option
    /// by its letter (or true/false); anything else is never counted against a child (ADR-0026).
    public static func interpret(
        _ transcriptions: [String], for presented: PresentedQuestion, matcher: AnswerMatcher = AnswerMatcher()
    ) -> VoiceReply {
        let heard = transcriptions.filter { !TextNormalizer.tokens($0).isEmpty }
        guard !heard.isEmpty else { return .silence }
        if let command = VoiceCommand.parse(heard) { return .command(command) }
        guard let choice = matcher.chosenOption(transcriptions: heard, presented: presented) else { return .garbled }
        return .answer(choice.index == presented.correctOptionIndex ? .correct : .incorrect, heard: choice.heard)
    }

    /// Words worth biasing the recogniser towards for this question.
    public static func hints(for presented: PresentedQuestion) -> [String] {
        var words = ["skip", "next", "repeat", "pause", "stop"]
        switch presented.question.type {
        case .trueFalse: words += ["true", "false"]
        case .multipleChoice: words += presented.optionLetters
        case .talkAbout: words += ["we're done", "all done", "finished"]
        }
        return words
    }
}
