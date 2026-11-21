/// What a child's spoken reply means on their turn (FEATURES §3.3, ADR-0018).
/// No speaker identification: whoever's turn it is gets the result.
public enum VoiceReply: Equatable, Sendable {
    /// A game command such as "skip" or "repeat".
    case command(VoiceCommand)
    /// An answer, judged against the question.
    case answer(AnswerOutcome, heard: String)
    /// Something was heard, but only "um", "hmm" and the like. Worth asking again once.
    case garbled
    /// Nothing was heard before the listening window closed.
    case silence

    private static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "er", "erm", "hmm", "hm", "mm", "ah", "oh", "eh", "huh", "ok", "okay",
        "wait", "let", "me", "think", "i", "dont", "know",
    ]

    /// Interprets every alternative transcription of one reply.
    public static func interpret(
        _ transcriptions: [String], for presented: PresentedQuestion, matcher: AnswerMatcher = AnswerMatcher()
    ) -> VoiceReply {
        let heard = transcriptions.filter { !TextNormalizer.tokens($0).isEmpty }
        guard !heard.isEmpty else { return .silence }
        if let command = VoiceCommand.parse(heard) { return .command(command) }
        switch matcher.match(transcriptions: heard, to: presented) {
        case .correct(let text):
            return .answer(.correct, heard: text)
        case .incorrect(let text):
            let allFiller = heard.allSatisfy { TextNormalizer.tokens($0).allSatisfy(fillers.contains) }
            return allFiller ? .garbled : .answer(.incorrect, heard: text)
        case .noAnswer:
            return .silence
        }
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
