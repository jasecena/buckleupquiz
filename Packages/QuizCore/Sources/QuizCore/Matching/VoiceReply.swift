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

    /// Interprets every alternative transcription of one reply. A wrong answer has to name one
    /// of the other options; random words never count against a child (ADR-0018).
    public static func interpret(
        _ transcriptions: [String], for presented: PresentedQuestion, matcher: AnswerMatcher = AnswerMatcher()
    ) -> VoiceReply {
        let heard = transcriptions.filter { !TextNormalizer.tokens($0).isEmpty }
        guard !heard.isEmpty else { return .silence }
        if let command = VoiceCommand.parse(heard) { return .command(command) }
        if case .correct(let text) = matcher.match(transcriptions: heard, to: presented) {
            return .answer(.correct, heard: text)
        }
        if let options = presented.options,
           let picked = heard.first(where: { matcher.chosenOption($0, options: options, presented: presented) != nil }) {
            return .answer(.incorrect, heard: picked)
        }
        return .garbled
    }

    /// Words worth biasing the recogniser towards for this question.
    public static func hints(for presented: PresentedQuestion) -> [String] {
        var words = ["skip", "next", "repeat", "pause", "stop"]
        switch presented.question.type {
        case .trueFalse: words += ["true", "false", "yes", "no"]
        case .multipleChoice: words += presented.optionLetters + (presented.options ?? [])
        case .talkAbout: words += ["we're done", "all done", "finished"]
        }
        return words
    }
}
