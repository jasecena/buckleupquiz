import Foundation
import Observation
import QuizCore
import SwiftData

/// Family members, persisted with SwiftData (ADR-0009, ADR-0015).
///
/// Players are never deleted, only renamed (ADR-0025): each one keeps the questions they've had,
/// so the family's allowance and review boxes stay right, and there's nothing to reconcile
/// across devices and backups.
@MainActor
@Observable
final class PlayerStore {
    static let maxPlayers = 6
    static let ageRange = 4...14
    /// Bright, distinct colours; each new player gets the first unused one.
    static let palette = ["#E84393", "#2E86DE", "#00B894", "#F39C12", "#6C5CE7", "#D63031"]

    private(set) var players: [PlayerProfile] = []
    /// Called after any change, so the backup stays current.
    @ObservationIgnored var onChange: (() -> Void)?
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

    // MARK: Backup (ADR-0023)

    /// One player as stored in the backup.
    struct Snapshot: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var age: Int
        var ageSetAt: Date
        var colorHex: String
        var createdAt: Date
        var learning: LearningRecord
        var stats: PlayerStats
    }

    func snapshot() -> [Snapshot] {
        players.map {
            Snapshot(id: $0.id, name: $0.name, age: $0.age, ageSetAt: $0.ageSetAt, colorHex: $0.colorHex,
                     createdAt: $0.createdAt, learning: $0.learning, stats: $0.stats)
        }
    }

    /// Brings players back from a backup: missing ones are re-created with their progress, and
    /// existing ones keep the more recent answer for each question and the fuller scores.
    func merge(_ snapshots: [Snapshot]) {
        for snap in snapshots {
            if let profile = players.first(where: { $0.id == snap.id }) {
                var learning = profile.learning
                learning.mergeKeepingLatest(snap.learning)
                if learning != profile.learning { profile.learning = learning }
                if snap.stats.attempted > profile.stats.attempted || snap.stats.points > profile.stats.points {
                    profile.stats = snap.stats
                }
            } else if players.count < Self.maxPlayers {
                let profile = PlayerProfile(name: snap.name, age: snap.age, colorHex: snap.colorHex, now: snap.ageSetAt)
                profile.id = snap.id
                profile.createdAt = snap.createdAt
                profile.learning = snap.learning
                profile.stats = snap.stats
                context.insert(profile)
            }
        }
        try? context.save()
        reload()
    }

    func profile(id: String) -> PlayerProfile? {
        players.first { $0.id.uuidString == id }
    }

    /// Leitner boxes for these players, keyed the way `QuizSession` expects (ADR-0016).
    func learning(for profiles: [PlayerProfile]) -> [String: LearningRecord] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0.learning) })
    }

    /// Lifetime scores, keyed the way `QuizSession` expects.
    func stats(for profiles: [PlayerProfile]) -> [String: PlayerStats] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0.stats) })
    }

    /// Saves each player's boxes after a session.
    func recordLearning(_ learning: [String: LearningRecord]) {
        record(SessionSummary(learning: learning, stats: [:]))
    }

    /// Saves boxes and adds the session's scores to each player's lifetime stats.
    func record(_ summary: SessionSummary) {
        for profile in players {
            let id = profile.id.uuidString
            if let newer = summary.learning[id] {
                var record = profile.learning
                record.merge(newer)
                profile.learning = record
            }
            if let session = summary.stats[id], session.attempted > 0 {
                profile.stats = profile.stats.adding(session)
            }
        }
        save()
    }

    /// A grown-up's score correction after a game, added to the lifetime points.
    func adjustPoints(for playerID: String, by change: Int) {
        guard let profile = players.first(where: { $0.id.uuidString == playerID }) else { return }
        var stats = profile.stats
        stats.points = max(0, stats.points + change)
        profile.stats = stats
        save()
    }

    private func save() {
        try? context.save()
        reload()
        onChange?()
    }

    private func reload() {
        let descriptor = FetchDescriptor<PlayerProfile>(sortBy: [SortDescriptor(\.createdAt)])
        players = (try? context.fetch(descriptor)) ?? []
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
