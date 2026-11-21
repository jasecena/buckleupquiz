import Foundation
import Observation
import QuizCore
import SwiftData

/// Family members, persisted with SwiftData (ADR-0009, ADR-0015).
@MainActor
@Observable
final class PlayerStore {
    static let maxPlayers = 6
    static let ageRange = 4...14
    /// Bright, distinct colours; each new player gets the first unused one.
    static let palette = ["#E84393", "#2E86DE", "#00B894", "#F39C12", "#6C5CE7", "#D63031"]

    private(set) var players: [PlayerProfile] = []
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        reload()
    }

    /// On-disk store. iCloud sync stays off until ADR-0012 is accepted.
    static func live() -> PlayerStore {
        do {
            let config = ModelConfiguration("Players", cloudKitDatabase: .none)
            return PlayerStore(container: try ModelContainer(for: PlayerProfile.self, configurations: config))
        } catch {
            return inMemory()
        }
    }

    /// For tests and previews.
    static func inMemory() -> PlayerStore {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return PlayerStore(container: try ModelContainer(for: PlayerProfile.self, configurations: config))
        } catch {
            fatalError("Could not create an in-memory player store: \(error)")
        }
    }

    var canAddMore: Bool { players.count < Self.maxPlayers }

    var nextColor: String {
        Self.palette.first { colour in !players.contains { $0.colorHex == colour } }
            ?? Self.palette[players.count % Self.palette.count]
    }

    @discardableResult
    func add(name: String, age: Int, colorHex: String? = nil) -> PlayerProfile? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAddMore, !name.isEmpty else { return nil }
        let profile = PlayerProfile(name: name, age: age.clamped(to: Self.ageRange), colorHex: colorHex ?? nextColor)
        context.insert(profile)
        save()
        return profile
    }

    func update(_ profile: PlayerProfile, name: String, age: Int, colorHex: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { profile.name = name }
        let age = age.clamped(to: Self.ageRange)
        if age != profile.currentAge() {
            profile.age = age
            profile.ageSetAt = .now
        }
        profile.colorHex = colorHex
        save()
    }

    func delete(_ profile: PlayerProfile) {
        context.delete(profile)
        save()
    }

    func profile(id: String) -> PlayerProfile? {
        players.first { $0.id.uuidString == id }
    }

    /// Seen-question ids for these players, keyed the way `QuizSession` expects.
    func seenQuestionIDs(for profiles: [PlayerProfile]) -> [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, Set($0.seenQuestionIDs)) })
    }

    /// Merges what each player heard in a session.
    func recordSeen(_ seen: [String: Set<String>]) {
        for profile in players {
            guard let ids = seen[profile.id.uuidString], !ids.isEmpty else { continue }
            profile.seenQuestionIDs = Array(Set(profile.seenQuestionIDs).union(ids)).sorted()
        }
        save()
    }

    private func save() {
        try? context.save()
        reload()
    }

    private func reload() {
        let descriptor = FetchDescriptor<PlayerProfile>(sortBy: [SortDescriptor(\.createdAt)])
        players = (try? context.fetch(descriptor)) ?? []
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
