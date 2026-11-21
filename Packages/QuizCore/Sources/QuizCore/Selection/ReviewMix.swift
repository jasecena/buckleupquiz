/// What a turn is for (ADR-0016).
public enum TurnKind: String, Sendable, Hashable, Codable {
    /// A question the player hasn't had, preferably one nobody in the family has had.
    case new
    /// One of the player's own Leitner reviews that is due.
    case ownReview
    /// A question another family member played in the last few days, now for this player.
    case sharedReview
}

/// Keeps it a game, not a drill: about 80% of each session is new questions, 10% the
/// player's own reviews and 10% questions the others had recently. Reviews land at random
/// spots, never first. When one kind runs out, the turn falls back to another.
public enum ReviewMix {
    public static let ownShare = 0.10
    public static let sharedShare = 0.10
    /// Endless sessions are planned in blocks of this many turns.
    public static let endlessBlock = 20
    /// How far back "questions the others had recently" looks, in days.
    public static let sharedLookback = 7

    public static func plan(turns: Int, using rng: inout some RandomNumberGenerator) -> [TurnKind] {
        guard turns > 0 else { return [] }
        let own = Int((Double(turns) * ownShare).rounded())
        let shared = Int((Double(turns) * sharedShare).rounded())
        var rest = Array(repeating: TurnKind.ownReview, count: own)
            + Array(repeating: TurnKind.sharedReview, count: shared)
        rest = Array(rest.prefix(turns - 1))
        rest += Array(repeating: TurnKind.new, count: turns - 1 - rest.count)
        rest.shuffle(using: &rng)
        return [.new] + rest
    }
}
