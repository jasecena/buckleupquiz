import Foundation

/// Result of judging a spoken answer.
public enum MatchOutcome: Equatable, Sendable {
    /// One of the transcriptions matched. `heard` is the one that did.
    case correct(heard: String)
    /// Something was heard but it didn't match.
    case incorrect(heard: String)
    /// Nothing usable was heard.
    case noAnswer
}

/// Judges spoken answers against a presented question (FEATURES §3.4).
/// Pure and deterministic, so the rules are pinned down by unit tests.
public struct AnswerMatcher: Sendable {
    /// Option text may be wrapped in a few filler words ("I think it's Hobart"),
    /// but long rambles that list many guesses are not accepted.
    public var maxExtraWords = 4
    /// For long choice options, the share of the option's key words that must be heard.
    public var optionOverlapThreshold = 0.5

    public init() {}

    /// Checks every alternative transcription; any match counts.
    public func match(transcriptions: [String], to presented: PresentedQuestion) -> MatchOutcome {
        let heard = transcriptions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !TextNormalizer.tokens($0).isEmpty }
        guard let first = heard.first else { return .noAnswer }
        for transcript in heard where isCorrect(transcript, presented) {
            return .correct(heard: transcript)
        }
        return .incorrect(heard: first)
    }

    public func isCorrect(_ transcript: String, _ presented: PresentedQuestion) -> Bool {
        let q = presented.question
        switch q.type {
        case .talkAbout:
            return false
        case .multipleChoice, .trueFalse:
            guard let options = presented.options, let correct = presented.correctOptionIndex else { return false }
            return chosenOption(transcript, options: options, presented: presented) == correct
        }
    }

    // MARK: - Choice questions

    private static let letterSounds: [[String]] = [
        ["a", "ay", "eh", "aye", "hey"],
        ["b", "be", "bee", "bea", "bi"],
        ["c", "see", "sea", "si", "cee"],
        ["d", "dee"],
        ["e"],
        ["f", "ef", "eff"],
    ]
    private static let letterFillers: Set<String> = [
        "option", "answer", "letter", "its", "it", "is", "i", "think", "say", "said", "pick", "choose", "go", "with",
        "the", "um", "uh", "umm", "er", "erm", "hmm", "oh", "so", "yeah", "ok", "okay",
    ]
    private static let trueWords: Set<String> = ["true", "yes", "yeah", "yep", "right", "correct", "its true"]
    private static let falseWords: Set<String> = ["false", "no", "nope", "wrong", "not true", "its false", "incorrect"]
    private static let stopWords: Set<String> = [
        "to", "and", "or", "of", "it", "is", "be", "if", "them", "they", "theyre", "their", "you", "your", "i",
        "a", "an", "the", "at", "in", "on", "for", "with", "my", "me", "so", "just", "that", "this", "are",
    ]

    /// Which option the child chose, or nil if unclear / hedged between options.
    func chosenOption(_ transcript: String, options: [String], presented: PresentedQuestion) -> Int? {
        var transcript = transcript
        var raw = TextNormalizer.tokens(transcript)
        // Spelled-out initials ("W A", "W.A.") are one word: "wa".
        if raw.count > 1, raw.allSatisfy({ $0.count == 1 && $0.first?.isLetter == true }) {
            transcript = raw.joined()
            raw = [transcript]
        }

        // 1. Option letter: "B", "option B", "I think it's C".
        let core = raw.filter { !Self.letterFillers.contains($0) }
        if presented.question.type != .trueFalse, core.count == 1 {
            for (i, sounds) in Self.letterSounds.prefix(options.count).enumerated() where sounds.contains(core[0]) {
                return i
            }
        }

        // 2. True/false synonyms.
        if presented.question.type == .trueFalse {
            let said = TextNormalizer.normalize(transcript)
            let trueIndex = options.firstIndex { TextNormalizer.normalize($0) == "true" }
            let falseIndex = options.firstIndex { TextNormalizer.normalize($0) == "false" }
            if Self.trueWords.contains(said) { return trueIndex }
            if Self.falseWords.contains(said) { return falseIndex }
        }

        // 3. Option text (plus accepted answers for the correct option).
        var exact: [Int] = []
        var contained: [Int] = []
        for (i, option) in options.enumerated() {
            var targets = [option]
            if i == presented.correctOptionIndex { targets += presented.question.acceptedAnswers }
            let best = targets.map { matchesPhrase(heard: transcript, target: $0) }.max() ?? .none
            if best == .whole { exact.append(i) }
            if best >= .contained { contained.append(i) }
        }
        if exact.count == 1 { return exact[0] }
        if contained.count == 1 { return contained[0] }
        if contained.count > 1 {
            // Overlapping options ("help them up" vs "help them up and ask..."): the longest wins,
            // but only if it is strictly longer — otherwise the child named several options.
            let lengths = contained.map { (i: $0, n: TextNormalizer.normalizedTokens(options[$0]).count) }
                .sorted { $0.n > $1.n }
            return lengths[0].n > lengths[1].n ? lengths[0].i : nil
        }

        // 4. Key-word overlap for long options ("help them up" for
        //    "Help them up and ask if they're okay").
        let heardWords = Set(TextNormalizer.normalizedTokens(transcript)).subtracting(Self.stopWords)
        guard !heardWords.isEmpty else { return nil }
        // Short options (one or two key words) must be said whole, so "South Australia" never
        // passes for "Western Australia"; "West Australia" still does (a word's start counts).
        let scores: [(i: Int, score: Double)] = options.enumerated().map { i, option in
            let keys = Set(TextNormalizer.normalizedTokens(option)).subtracting(Self.stopWords)
            guard !keys.isEmpty else { return (i, 0) }
            let hits = keys.filter { key in heardWords.contains { keyWord($0, matches: key) } }.count
            let score = Double(hits) / Double(keys.count)
            return (i, keys.count <= 2 && score < 1 ? 0 : score)
        }.sorted { $0.score > $1.score }
        guard scores[0].score >= optionOverlapThreshold else { return nil }
        if scores.count > 1, scores[1].score >= scores[0].score { return nil }
        return scores[0].i
    }

    // MARK: - Phrase matching

    enum PhraseMatch: Int, Comparable {
        case none = 0, contained = 1, whole = 2
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    }

    /// Whole-phrase fuzzy match, or the target appearing inside a short transcript.
    func matchesPhrase(heard: String, target: String) -> PhraseMatch {
        let h = TextNormalizer.normalizedTokens(heard)
        let t = TextNormalizer.normalizedTokens(target)
        guard !h.isEmpty, !t.isEmpty else { return .none }
        if fuzzyEqual(h.joined(separator: " "), t.joined(separator: " ")) { return .whole }
        guard h.count > t.count, h.count <= t.count + maxExtraWords else { return .none }
        for start in 0...(h.count - t.count) {
            let window = h[start..<(start + t.count)].joined(separator: " ")
            if fuzzyEqual(window, t.joined(separator: " ")) { return .contained }
        }
        return .none
    }

    /// A heard word matches an option's key word if it's close, or a clear start of it
    /// ("west" for "western").
    func keyWord(_ heard: String, matches key: String) -> Bool {
        if fuzzyEqual(heard, key) { return true }
        return heard.count >= 4 && !heard.contains(where: \.isNumber) && key.hasPrefix(heard)
    }

    /// Exact for anything containing digits ("21" must never equal "22"), otherwise
    /// Levenshtein within a length-scaled threshold.
    func fuzzyEqual(_ heard: String, _ target: String) -> Bool {
        if heard == target { return true }
        if heard.contains(where: \.isNumber) || target.contains(where: \.isNumber) { return false }
        let allowed = Levenshtein.threshold(forLength: target.count)
        guard allowed > 0, abs(heard.count - target.count) <= allowed else { return false }
        return Levenshtein.distance(heard, target) <= allowed
    }
}
