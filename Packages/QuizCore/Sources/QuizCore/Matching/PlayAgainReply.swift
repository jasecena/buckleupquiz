/// The reply to "If you'd like to play some more, just say new game!" at the end of a voice game
/// (product decision, 2026-11-22). Strict on purpose: a cheer like "Yes, I won!" or chatter in
/// the car must never start a game, so only a clear ask for more counts, and "no" always wins.
public enum PlayAgainReply: Equatable, Sendable {
    case newGame
    case noThanks

    /// Longer than this is chatter or the radio, not a reply.
    static let maxWords = 8

    private static let noWords: Set<String> = ["no", "nope", "nah", "stop", "done", "finished", "enough", "later"]
    private static let newGameWords: Set<String> = ["again", "another", "more"]
    private static let newGamePhrases: [[String]] = [
        ["new", "game"], ["new", "games"], ["new", "one"], ["start"], ["lets", "play"], ["keep", "going"],
        ["yes", "please"], ["play", "more"],
    ]

    /// The reply in any of the transcriptions, or nil for silence, mumbles and anything else.
    public static func parse(_ transcriptions: [String]) -> PlayAgainReply? {
        let replies = transcriptions.map(TextNormalizer.tokens).filter { !$0.isEmpty && $0.count <= maxWords }
        if replies.contains(where: { !noWords.isDisjoint(with: $0) || contains(["not", "now"], in: $0) }) {
            return .noThanks
        }
        let asksForMore = replies.contains { words in
            !newGameWords.isDisjoint(with: words) || newGamePhrases.contains { contains($0, in: words) }
        }
        return asksForMore ? .newGame : nil
    }

    /// Words worth biasing the recogniser towards.
    public static let hints = ["new game", "play again", "one more", "again", "no thanks"]

    private static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
}
