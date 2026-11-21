import Foundation
import Observation
import QuizCore

/// User settings (FEATURES §2.5), persisted to `UserDefaults` as one JSON blob.
/// Players live in SwiftData (`PlayerStore`).
struct AppSettings: Codable, Equatable, Sendable {
    var listen = ListenSettings()
    var voiceIdentifier: String?
    var speechRate: Float = 0.45
    /// Lower music volume instead of stopping it.
    var duckOthers = true
    /// "Parent mode": include Talk About prompts (FEATURES §4.3).
    /// Parent mode. Off by default: Talk About needs a grown-up to chat with.
    var includeTalkAbout = false
    /// Players picked last time ("Who's playing?"), as `PlayerProfile.id` strings.
    var selectedPlayerIDs: [String] = []
    var lastSessionLength: SessionLength = .questions(10)
    var hasCompletedOnboarding = false

    var voice: VoiceSettings { VoiceSettings(identifier: voiceIdentifier, rate: speechRate) }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case listen, voiceIdentifier, speechRate, duckOthers, includeTalkAbout
        case selectedPlayerIDs, lastSessionLength, hasCompletedOnboarding
    }

    /// Key by key with defaults, so settings saved by older builds (testers!) never get wiped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        listen = (try? c.decodeIfPresent(ListenSettings.self, forKey: .listen)) ?? d.listen
        voiceIdentifier = try? c.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        speechRate = (try? c.decodeIfPresent(Float.self, forKey: .speechRate)) ?? d.speechRate
        duckOthers = (try? c.decodeIfPresent(Bool.self, forKey: .duckOthers)) ?? d.duckOthers
        includeTalkAbout = (try? c.decodeIfPresent(Bool.self, forKey: .includeTalkAbout)) ?? d.includeTalkAbout
        selectedPlayerIDs = (try? c.decodeIfPresent([String].self, forKey: .selectedPlayerIDs)) ?? d.selectedPlayerIDs
        lastSessionLength = (try? c.decodeIfPresent(SessionLength.self, forKey: .lastSessionLength)) ?? d.lastSessionLength
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding
    }
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
