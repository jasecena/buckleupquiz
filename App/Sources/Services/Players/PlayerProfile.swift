import Foundation
import QuizCore
import SwiftData

/// A family member who plays (ADR-0015). Their age picks the question band.
///
/// Modelled to be CloudKit-sync ready (ADR-0009): every property has a default,
/// no unique constraints, no required relationships.
@Model
final class PlayerProfile {
    var id: UUID = UUID()
    var name: String = ""
    /// Age when it was last entered. `currentAge` adds the years since, so a child
    /// moves up a band on their own as time passes.
    var age: Int = 8
    var ageSetAt: Date = Date.now
    var colorHex: String = "#2E86DE"
    var createdAt: Date = Date.now
    /// This player's Leitner boxes (ADR-0016), JSON-encoded `LearningRecord`.
    /// Stored as data so the schema stays simple and CloudKit-friendly.
    var learningData: Data = Data()
    /// Lifetime scores (`PlayerStats`, JSON) from voice-answer games: points, streaks, per topic.
    var statsData: Data = Data()

    init(name: String, age: Int, colorHex: String, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.age = age
        self.ageSetAt = now
        self.colorHex = colorHex
        self.createdAt = now
        self.learningData = Data()
        self.statsData = Data()
    }

    func currentAge(now: Date = .now) -> Int {
        let years = Calendar.current.dateComponents([.year], from: ageSetAt, to: now).year ?? 0
        return age + max(0, years)
    }

    var ageBand: AgeBand { AgeBand(age: currentAge()) }

    var stats: PlayerStats {
        get { (try? JSONDecoder().decode(PlayerStats.self, from: statsData)) ?? PlayerStats() }
        set { statsData = (try? JSONEncoder().encode(newValue)) ?? statsData }
    }

    var learning: LearningRecord {
        get { (try? JSONDecoder().decode(LearningRecord.self, from: learningData)) ?? LearningRecord() }
        set { learningData = (try? JSONEncoder().encode(newValue)) ?? learningData }
    }

    /// The value type the quiz engine works with.
    var quizPlayer: Player { Player(id: id.uuidString, name: name, age: currentAge()) }
}
