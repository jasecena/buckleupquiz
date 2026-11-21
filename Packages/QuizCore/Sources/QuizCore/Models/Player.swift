/// Someone taking turns in a session. The free tier uses a single anonymous player.
public struct Player: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var ageBand: AgeBand
    /// Optional exact age, used to filter questions with `minAge`.
    public var age: Int?

    public init(id: String, name: String, ageBand: AgeBand, age: Int? = nil) {
        self.id = id
        self.name = name
        self.ageBand = ageBand
        self.age = age
    }

    /// The single player used by Listen mode (free tier). Its name is never spoken.
    public static func listener(ageBand: AgeBand) -> Player {
        Player(id: "listener", name: "", ageBand: ageBand)
    }
}
