/// Everything the app says, in one place so tone stays consistent (FEATURES §0, §3.3, §4.3).
/// English only for v1; this is the seam for localisation later.
public enum Phrases {
    public static let intro = "Buckle up, kids… question one!"
    public static let outroPrefix = "That's the end of the ride!"
    public static let welcomeBack = "Welcome back! Let's keep going."
    public static let listening = "I'm listening."
    public static let greatChat = "Great chat!"
    /// Said before a review question, so it feels like a callback, not a repeat.
    public static let ownReviewIntro = "Here's one from before. Do you remember?"
    public static let sharedReviewIntro = "This one came up for someone else. Let's see!"
    public static let voiceTip = "Say your answer after the beep!"
    public static let pausedByVoice = "Paused. Press play when you're ready."
    public static let talkItOver = "Take your time and talk it over. Press next when you're ready."

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
        let lead = (category == .values || category == .safety)
            ? "The best choice is…" : "The answer is…"
        return "\(lead) \(answer.trimmedSentence)!"
    }

    /// Spoken feedback after a voice answer. Right answers get a cheer. Anything else just
    /// shares the answer, exactly as Listen mode does: no "wrong", no "time's up", no
    /// "I didn't hear you". It's about knowledge and joy, never failure (ADR-0018).
    public static func feedback(
        _ outcome: AnswerOutcome, presented: PresentedQuestion, category: Topic.Category?,
        using rng: inout some RandomNumberGenerator
    ) -> String {
        switch outcome {
        case .correct:
            return cheers.randomElement(using: &rng) ?? "Correct!"
        case .incorrect, .timedOut, .unheard:
            return answerReveal(presented, category: category)
        case .skipped:
            return "Let's skip that one."
        case .notScored:
            return greatChat
        }
    }

    /// Cheers a streak on top of "Correct!": "That's three in a row!"
    public static func streak(_ count: Int) -> String? {
        count >= 3 ? "That's \(NumberWords.spell(count)) in a row!" : nil
    }

    /// "Mia earned the High Five badge!"
    public static func badgeEarned(_ badge: Badge, by player: Player) -> String {
        player.name.isEmpty ? "You earned the \(badge.title) badge!" : "\(player.name) earned the \(badge.title) badge!"
    }

    /// End of a Listen-mode session (no scores): "That's the end of the ride! Great job, Mia and Leo!"
    public static func listenOutro(players: [Player]) -> String {
        let names = players.map(\.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return "\(outroPrefix) Great listening, everyone!" }
        return "\(outroPrefix) Great job, \(listJoined(names))!"
    }

    /// End-of-session announcement, e.g. "Mia wins with 80 points! Leo got 60 points!"
    /// Nobody is ever announced with zero points: they get "Great listening" instead.
    public static func scoreAnnouncement(_ entries: [ScoreboardEntry]) -> String {
        let named = entries.filter { !$0.player.name.isEmpty }
        guard named.contains(where: { $0.points > 0 }) else { return listenOutro(players: named.map(\.player)) }
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
            parts.append(entry.points > 0
                ? "\(entry.player.name) got \(points(entry.points))!"
                : "Great listening, \(entry.player.name)!")
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
