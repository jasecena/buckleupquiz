import Foundation
import Observation
import QuizCore

/// The app's dependency container. Views read it from the SwiftUI environment;
/// tests and previews build one with fakes (ADR-0011).
@MainActor
@Observable
final class AppEnvironment {
    enum ContentState {
        case loading
        case loaded(QuestionBank)
        case failed(String)
    }

    private(set) var content: ContentState = .loading
    let settings: SettingsStore
    let entitlements: EntitlementStore
    let players: PlayerStore
    let questionSource: any QuestionSource
    let makeListenDependencies: @MainActor (SettingsStore) -> ListenSessionModel.Dependencies

    init(
        settings: SettingsStore,
        entitlements: EntitlementStore,
        players: PlayerStore,
        questionSource: any QuestionSource,
        makeListenDependencies: @escaping @MainActor (SettingsStore) -> ListenSessionModel.Dependencies
    ) {
        self.settings = settings
        self.entitlements = entitlements
        self.players = players
        self.questionSource = questionSource
        self.makeListenDependencies = makeListenDependencies
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            settings: SettingsStore(),
            entitlements: EntitlementStore(),
            players: PlayerStore.live(),
            questionSource: BundledContent.source(),
            makeListenDependencies: { settings in
                ListenSessionModel.Dependencies(
                    speech: SystemSpeechOutput(voiceSettings: { [weak settings] in settings?.settings.voice ?? VoiceSettings() }),
                    cues: EngineCuePlayer(),
                    audioSession: AudioSessionController(),
                    nowPlaying: NowPlayingController()
                )
            }
        )
    }

    var bank: QuestionBank? {
        if case .loaded(let bank) = content { return bank }
        return nil
    }

    func loadContent() async {
        guard bank == nil else { return }
        do {
            content = .loaded(try await questionSource.loadBank())
        } catch {
            content = .failed(String(describing: error))
        }
    }

    /// A Listen-mode session for the chosen players, taking turns, each with questions
    /// for their own age (ADR-0015).
    func makeListenSession(topics: [String], profiles: [PlayerProfile], length: SessionLength) -> ListenSessionModel? {
        guard let bank, !profiles.isEmpty else { return nil }
        let s = settings.settings
        let config = SessionConfig(topics: topics, players: profiles.map(\.quizPlayer), length: length,
                                   includeTalkAbout: s.includeTalkAbout)
        let model = ListenSessionModel(
            bank: bank, config: config, settings: s.listen, duckOthers: s.duckOthers,
            dependencies: makeListenDependencies(settings),
            // The whole family's boxes: absent players' recent questions can be shared, and
            // nobody gets a question someone else already had today (ADR-0016).
            learning: players.learning(for: players.players), day: LearningDay.number(),
            playerColors: Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0.colorHex) }))
        model.onFinish = { [weak players] learning in players?.recordLearning(learning) }
        return model
    }
}
