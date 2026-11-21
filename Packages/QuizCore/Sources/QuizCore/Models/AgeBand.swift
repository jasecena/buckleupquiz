/// The three age bands content is written for.
public enum AgeBand: String, Codable, CaseIterable, Sendable, Hashable, Comparable {
    case sixToEight = "6-8"
    case nineToTen = "9-10"
    case elevenToTwelve = "11-12"

    /// Human-readable label, e.g. "Ages 6–8".
    public var displayName: String {
        switch self {
        case .sixToEight: "Ages 6–8"
        case .nineToTen: "Ages 9–10"
        case .elevenToTwelve: "Ages 11–12"
        }
    }

    public var ageRange: ClosedRange<Int> {
        switch self {
        case .sixToEight: 6...8
        case .nineToTen: 9...10
        case .elevenToTwelve: 11...12
        }
    }

    public static func < (lhs: AgeBand, rhs: AgeBand) -> Bool {
        lhs.ageRange.lowerBound < rhs.ageRange.lowerBound
    }
}
