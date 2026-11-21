/// A question as it is asked in a session: choice options shuffled, correct option tracked.
public struct PresentedQuestion: Hashable, Sendable {
    public static let letters = ["A", "B", "C", "D", "E", "F"]

    public let question: Question
    /// Options in the order they are read out. `nil` for talkAbout prompts.
    public let options: [String]?
    /// Index of the correct option in `options`.
    public let correctOptionIndex: Int?

    public init(question: Question, options: [String]?, correctOptionIndex: Int?) {
        self.question = question
        self.options = options
        self.correctOptionIndex = correctOptionIndex
    }

    /// Presents `question`, shuffling choice options (FEATURES §4.4) except true/false,
    /// whose order stays "True, False".
    public init(question: Question, shuffleOptions: Bool, using rng: inout some RandomNumberGenerator) {
        var options = question.choiceOptions
        if shuffleOptions, question.type != .trueFalse {
            options?.shuffle(using: &rng)
        }
        self.question = question
        self.options = options
        if let options, let answer = question.answer {
            let target = TextNormalizer.normalize(answer)
            correctOptionIndex = options.firstIndex { TextNormalizer.normalize($0) == target }
        } else {
            correctOptionIndex = nil
        }
    }

    /// "A", "B", ... for each option.
    public var optionLetters: [String] {
        Array(Self.letters.prefix(options?.count ?? 0))
    }

    /// The correct answer as it should be spoken/shown, e.g. "B: Hobart" or "True".
    public var answerText: String? {
        if question.type == .trueFalse { return question.answer }
        if let options, let i = correctOptionIndex, i < Self.letters.count {
            return "\(Self.letters[i]): \(options[i])"
        }
        return question.answer
    }
}
