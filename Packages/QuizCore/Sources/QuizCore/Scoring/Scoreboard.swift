public struct ScoreboardEntry: Hashable, Sendable {
    public let player: Player
    public let points: Int
    /// 1-based; tied players share a rank.
    public let rank: Int
}

public enum Scoreboard {
    /// Players ordered by points (ties keep turn order and share a rank).
    public static func rank(players: [Player], scores: ScoreKeeper) -> [ScoreboardEntry] {
        let sorted = players.enumerated()
            .map { (order: $0.offset, player: $0.element, points: scores.stats(for: $0.element.id).points) }
            .sorted { $0.points != $1.points ? $0.points > $1.points : $0.order < $1.order }
        var entries: [ScoreboardEntry] = []
        for (i, row) in sorted.enumerated() {
            let rank = (i > 0 && row.points == sorted[i - 1].points) ? entries[i - 1].rank : i + 1
            entries.append(ScoreboardEntry(player: row.player, points: row.points, rank: rank))
        }
        return entries
    }
}
