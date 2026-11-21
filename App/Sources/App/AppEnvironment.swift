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
    /// Anonymous error reports (ADR-0020).
    let telemetry: Telemetry
    let makeListenDependencies: @MainActor (SettingsStore) -> ListenSessionModel.Dependencies
    @ObservationIgnored private var metricKit: MetricKitCollector?

    init(
        settings: SettingsStore,
        entitlements: EntitlementStore,
        players: PlayerStore,
        questionSource: any QuestionSource,
        telemetry: Telemetry? = nil,
        makeListenDependencies: @escaping @MainActor (SettingsStore) -> ListenSessionModel.Dependencies
    ) {
        self.settings = settings
        self.entitlements = entitlements
        self.players = players
        self.questionSource = questionSource
        self.telemetry = telemetry ?? Telemetry(endpoint: nil, fileURL: nil, isEnabled: { false })
        self.makeListenDependencies = makeListenDependencies
    }

    static func live() -> AppEnvironment {
        let settings = SettingsStore()
        let telemetry = Telemetry(endpoint: Telemetry.configuredEndpoint,
                                  isEnabled: { [weak settings] in settings?.settings.shareDiagnostics ?? false })
        let environment = AppEnvironment(
            settings: settings,
            entitlements: EntitlementStore(),
            players: PlayerStore.live(),
            questionSource: BundledContent.source(),
            telemetry: telemetry,
            makeListenDependencies: { settings in
                ListenSessionModel.Dependencies(
                    speech: SystemSpeechOutput(voiceSettings: { [weak settings] in settings?.settings.voice ?? VoiceSettings() }),
                    cues: EngineCuePlayer(),
                    audioSession: AudioSessionController(),
                    nowPlaying: NowPlayingController(),
                    telemetry: telemetry,
                    // On-device recognition only (ADR-0004); nil falls back to reading answers out.
                    listener: Self.makeListener(settings: settings, telemetry: telemetry)
                )
            }
        )
        environment.metricKit = MetricKitCollector(telemetry: telemetry)
        return environment
    }

    private static func makeListener(settings: SettingsStore, telemetry: Telemetry) -> SystemSpeechListener? {
        guard settings.settings.answerMode == .voice else { return nil }
        guard SystemSpeechListener.hasPermission else {
            telemetry.record("voice.noPermission", [:])
            return nil
        }
        guard let listener = SystemSpeechListener() else {
            telemetry.record("voice.noOnDeviceRecognizer", ["reason": SystemSpeechListener.lastProblem ?? "unknown"])
            return nil
        }
        listener.telemetry = telemetry
        return listener
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
            telemetry.record("content.loadFailed", ["error": String(describing: error)])
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
            answerMode: s.answerMode, mic: s.micPreference,
            // The whole family's boxes: absent players' recent questions can be shared, and
            // nobody gets a question someone else already had today (ADR-0016).
            learning: players.learning(for: players.players), lifetimeStats: players.stats(for: profiles),
            day: LearningDay.number(),
            playerColors: Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0.colorHex) }),
            showScoreboard: s.showScoreboard)
        model.onFinish = { [weak players] summary in players?.record(summary) }
        return model
    }
}
