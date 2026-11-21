/// Simple achievements (FEATURES §3.5).
public struct Badge: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
}

public enum BadgeRules {
    /// Minimum questions in a topic before an "Expert" badge can be earned.
    public static let expertMinimumAttempts = 10
    public static let expertAccuracy = 0.8

    public static func earned(by stats: PlayerStats, topics: [Topic]) -> [Badge] {
        var badges: [Badge] = []
        if stats.bestStreak >= 5 {
            badges.append(Badge(id: "streak-5", title: "High Five", detail: "5 correct in a row"))
        }
        if stats.bestStreak >= 10 {
            badges.append(Badge(id: "streak-10", title: "10 in a Row", detail: "10 correct in a row"))
        }
        for topic in topics {
            guard let t = stats.byTopic[topic.id],
                  t.attempted >= expertMinimumAttempts, t.accuracy >= expertAccuracy else { continue }
            badges.append(Badge(id: "expert-\(topic.id)", title: "\(topic.name) Expert",
                                detail: "80% or more in \(topic.name)"))
        }
        return badges
    }
}
