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
    let questionSource: any QuestionSource
    let makeListenDependencies: @MainActor (SettingsStore) -> ListenSessionModel.Dependencies

    init(
        settings: SettingsStore,
        entitlements: EntitlementStore,
        questionSource: any QuestionSource,
        makeListenDependencies: @escaping @MainActor (SettingsStore) -> ListenSessionModel.Dependencies
    ) {
        self.settings = settings
        self.entitlements = entitlements
        self.questionSource = questionSource
        self.makeListenDependencies = makeListenDependencies
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            settings: SettingsStore(),
            entitlements: EntitlementStore(),
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

    func makeListenSession(topics: [String], ageBand: AgeBand, length: SessionLength) -> ListenSessionModel? {
        guard let bank else { return nil }
        let s = settings.settings
        let config = SessionConfig(topics: topics, players: [.listener(ageBand: ageBand)], length: length,
                                   includeTalkAbout: s.includeTalkAbout)
        return ListenSessionModel(bank: bank, config: config, settings: s.listen, duckOthers: s.duckOthers,
                                  dependencies: makeListenDependencies(settings))
    }
}
