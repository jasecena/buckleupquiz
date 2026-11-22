import Foundation

/// Result of judging a spoken answer.
public enum MatchOutcome: Equatable, Sendable {
    /// The child picked the right option. `heard` is the transcription that picked it.
    case correct(heard: String)
    /// Something was heard, but it didn't clearly pick the right option.
    case incorrect(heard: String)
    /// Nothing usable was heard.
    case noAnswer
}

/// Judges spoken answers by the option letter only (ADR-0026): "B", "option B", "I think it's B".
/// True/false questions take "true" or "false". The option's words never count, so a wrong
/// answer can't be mistaken for a right one, and "Correct!" is only said for the right letter.
/// Pure and deterministic, so the rules are pinned down by unit tests.
public struct AnswerMatcher: Sendable {
    public init() {}

    /// Right only when the transcriptions clearly pick the correct option.
    public func match(transcriptions: [String], to presented: PresentedQuestion) -> MatchOutcome {
        let heard = transcriptions.filter { !TextNormalizer.tokens($0).isEmpty }
        guard let first = heard.first else { return .noAnswer }
        if let choice = chosenOption(transcriptions: heard, presented: presented),
           choice.index == presented.correctOptionIndex {
            return .correct(heard: choice.heard)
        }
        return .incorrect(heard: first)
    }

    /// The option the child picked. The recogniser gives several guesses at what was said; every
    /// guess that names an option must name the same one. If one hears "B" and another "D", the
    /// reply is unclear (nil) and listening carries on, rather than risk calling a wrong answer right.
    public func chosenOption(transcriptions: [String], presented: PresentedQuestion) -> (index: Int, heard: String)? {
        let picks = transcriptions.compactMap { text in chosenOption(text, presented: presented).map { (index: $0, heard: text) } }
        guard let first = picks.first, picks.allSatisfy({ $0.index == first.index }) else { return nil }
        return first
    }

    /// Which option one transcription picks, or nil if it doesn't name exactly one.
    func chosenOption(_ transcript: String, presented: PresentedQuestion) -> Int? {
        guard let options = presented.options else { return nil }
        switch presented.question.type {
        case .talkAbout:
            return nil
        case .trueFalse:
            let said = TextNormalizer.tokens(transcript).filter { !Self.fillers.contains($0) }
            guard said.count == 1 else { return nil }
            return options.firstIndex { TextNormalizer.normalize($0) == said[0] }
        case .multipleChoice:
            let said = TextNormalizer.tokens(transcript).filter { !Self.fillers.contains($0) }
            guard said.count == 1 else { return nil }
            return Self.letterSounds.prefix(options.count).firstIndex { $0.contains(said[0]) }
        }
    }

    /// How the recogniser may write each letter when it's said on its own.
    static let letterSounds: [Set<String>] = [
        ["a", "ay", "aye", "eh"],
        ["b", "be", "bee", "bea", "bi"],
        ["c", "see", "sea", "si", "cee"],
        ["d", "dee"],
        ["e"],
        ["f", "ef", "eff"],
    ]

    /// Words around the letter that don't change the answer: "Option B", "I think it's C".
    static let fillers: Set<String> = [
        "option", "answer", "letter", "its", "it", "is", "i", "think", "say", "said", "pick", "choose", "go", "with",
        "the", "um", "uh", "umm", "er", "erm", "hmm", "oh", "so", "yeah", "ok", "okay",
    ]
}
