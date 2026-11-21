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
    /// Parent mode: include Talk About prompts (FEATURES §4.3).
    /// Off by default: Talk About needs a grown-up to chat with.
    var includeTalkAbout = false
    /// Players picked last time ("Who's playing?"), as `PlayerProfile.id` strings.
    var selectedPlayerIDs: [String] = []
    var lastSessionLength: SessionLength = .questions(10)
    var hasCompletedOnboarding = false
    /// Players say their answers and the app keeps score (ADR-0018). Falls back to reading
    /// the answers out when the microphone can't be used.
    var answerMode: AnswerMode = .voice
    var micPreference: MicPreference = .automatic
    /// Send anonymous error reports so problems like a microphone that won't start can be
    /// fixed (ADR-0020). No names, answers, recordings or identifiers.
    var shareDiagnostics = true
    /// Bumped when a default changes, so saved settings can be moved to the new default once.
    /// 2: think time default 8 → 6 s.
    var version = 2

    var voice: VoiceSettings { VoiceSettings(identifier: voiceIdentifier, rate: speechRate) }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case listen, voiceIdentifier, speechRate, duckOthers, includeTalkAbout
        case selectedPlayerIDs, lastSessionLength, hasCompletedOnboarding, answerMode, micPreference
        case shareDiagnostics, version
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
        answerMode = (try? c.decodeIfPresent(AnswerMode.self, forKey: .answerMode)) ?? d.answerMode
        micPreference = (try? c.decodeIfPresent(MicPreference.self, forKey: .micPreference)) ?? d.micPreference
        shareDiagnostics = (try? c.decodeIfPresent(Bool.self, forKey: .shareDiagnostics)) ?? d.shareDiagnostics
        let savedVersion = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        if savedVersion < 2, listen.thinkTime == 8 { listen.thinkTime = d.listen.thinkTime }
        version = d.version
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
