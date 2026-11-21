/// Everything the app says, in one place so tone stays consistent (FEATURES §0, §3.3, §4.3).
/// English only for v1; this is the seam for localisation later.
public enum Phrases {
    public static let intro = "Buckle up, kids… question one!"
    public static let outroPrefix = "That's the end of the ride!"
    public static let welcomeBack = "Welcome back! Let's keep going."
    public static let listening = "I'm listening."
    public static let didntCatch = "Sorry, I didn't catch that. Say it again?"
    public static let greatChat = "Great chat!"

    public static let cheers = [
        "Correct!", "Correct! Awesome!", "Correct! You're a superstar!", "Correct! Nailed it!",
        "Correct! Brilliant!", "Correct! Fantastic!", "Correct! Way to go!",
    ]

    public static func questionNumber(_ n: Int) -> String {
        n == 1 ? intro : "Question \(NumberWords.spell(n))."
    }

    /// "Mia, this one's for you: What is…"
    public static func addressed(_ question: String, to player: Player?) -> String {
        guard let name = player?.name, !name.isEmpty else { return question }
        return "\(name), this one's for you: \(question)"
    }

    /// "A: laugh. B: help them up. C: keep playing."
    public static func options(_ presented: PresentedQuestion) -> String? {
        guard presented.question.type != .trueFalse, let options = presented.options, !options.isEmpty else {
            return nil
        }
        return zip(presented.optionLetters, options)
            .map { "\($0): \($1.trimmedSentence)." }
            .joined(separator: " ")
    }

    /// "The answer is… Hobart!"
    public static func answerReveal(_ presented: PresentedQuestion, category: Topic.Category?) -> String {
        guard let answer = presented.answerText else { return greatChat }
        let lead = (category == .values || category == .safety || presented.question.type == .scenario)
            ? "The best choice is…" : "The answer is…"
        return "\(lead) \(answer.trimmedSentence)!"
    }

    /// Spoken feedback after a voice answer. Never shames: values/safety topics get gentle wording.
    public static func feedback(
        _ outcome: AnswerOutcome, presented: PresentedQuestion, category: Topic.Category?,
        using rng: inout some RandomNumberGenerator
    ) -> String {
        let answer = presented.answerText?.trimmedSentence ?? ""
        let gentle = category == .values || category == .safety
        switch outcome {
        case .correct:
            return cheers.randomElement(using: &rng) ?? "Correct!"
        case .incorrect:
            return gentle ? "Good try! A kinder choice might be… \(answer)." : "Not quite, the answer was \(answer)."
        case .timedOut:
            return gentle ? "Time's up! A good choice is… \(answer)." : "Time's up! The answer was \(answer)."
        case .skipped:
            return "Let's skip that one."
        case .notScored:
            return greatChat
        }
    }

    /// End-of-session announcement, e.g. "Mia wins with 80 points! Leo got 60 points!"
    public static func scoreAnnouncement(_ entries: [ScoreboardEntry]) -> String {
        let named = entries.filter { !$0.player.name.isEmpty }
        guard !named.isEmpty else { return "\(outroPrefix) Great listening, everyone!" }
        if named.count == 1 {
            return "\(outroPrefix) \(named[0].player.name) got \(points(named[0].points))!"
        }
        var parts = ["\(outroPrefix) Here are the scores…"]
        let winners = named.filter { $0.rank == 1 }
        if winners.count > 1 {
            let names = listJoined(winners.map(\.player.name))
            parts.append("It's a tie! \(names) both got \(points(winners[0].points))!")
        } else {
            parts.append("\(winners[0].player.name) wins with \(points(winners[0].points))!")
        }
        for entry in named where entry.rank != 1 {
            parts.append("\(entry.player.name) got \(points(entry.points))!")
        }
        return parts.joined(separator: " ")
    }

    static func points(_ n: Int) -> String { n == 1 ? "1 point" : "\(n) points" }

    static func listJoined(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

extension String {
    /// Drops trailing sentence punctuation so phrases can add their own.
    var trimmedSentence: String {
        var s = self
        while let last = s.last, ".!?".contains(last) { s.removeLast() }
        return s
    }
}
