import Foundation
import Observation
import QuizCore

/// User settings (FEATURES §2.5), persisted to `UserDefaults` as one JSON blob.
/// Player profiles and stats move to SwiftData in M5 (ADR-0009).
struct AppSettings: Codable, Equatable, Sendable {
    var listen = ListenSettings()
    var voiceIdentifier: String?
    var speechRate: Float = 0.45
    /// Lower music volume instead of stopping it.
    var duckOthers = true
    /// "Parent mode": include Talk About prompts (FEATURES §4.3).
    var includeTalkAbout = true
    var lastAgeBand: AgeBand = .sixToEight
    var lastSessionLength: SessionLength = .questions(10)
    var hasCompletedOnboarding = false

    var voice: VoiceSettings { VoiceSettings(identifier: voiceIdentifier, rate: speechRate) }
}

@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet { if settings != oldValue { save() } }
    }

    private let defaults: UserDefaults
    private let key = "settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
