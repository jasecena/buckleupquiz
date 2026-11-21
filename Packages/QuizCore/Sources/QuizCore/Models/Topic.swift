/// A topic ("area") tile on the home screen. Loaded from `Content/topics.json`
/// so new topics can ship as content without code changes.
public struct Topic: Codable, Hashable, Identifiable, Sendable {
    public enum Category: String, Codable, Sendable, Hashable {
        case knowledge, values, safety
    }

    public var id: String
    public var name: String
    /// SF Symbol name used for the tile icon.
    public var symbol: String
    /// Tile colour as "#RRGGBB".
    public var color: String
    public var category: Category
    /// Unlocked in the free tier (FEATURES §2.1: three free topics).
    public var isFree: Bool
    /// Age bands this topic has content for.
    public var ageBands: [AgeBand]
    /// Content must be reviewed (by a parent/teacher, or with First Nations input) before release.
    public var requiresReview: Bool

    public init(
        id: String, name: String, symbol: String, color: String,
        category: Category, isFree: Bool, ageBands: [AgeBand] = AgeBand.allCases,
        requiresReview: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.category = category
        self.isFree = isFree
        self.ageBands = ageBands
        self.requiresReview = requiresReview
    }
}
