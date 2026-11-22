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
    /// New questions the family can have, and purchases (ADR-0022).
    let allowance: AllowanceStore
    let store: StoreService
    /// New questions without an app update (ADR-0031). nil when this build has downloads off.
    let contentUpdater: ContentUpdater?
    let makeListenDependencies: @MainActor (SettingsStore) -> ListenSessionModel.Dependencies
    @ObservationIgnored private var metricKit: MetricKitCollector?
    /// Progress kept in iCloud and the Keychain, so a reinstall picks up where it left off.
    @ObservationIgnored private var sync: ProgressSync?

    init(
        settings: SettingsStore,
        entitlements: EntitlementStore,
        players: PlayerStore,
        questionSource: any QuestionSource,
        telemetry: Telemetry? = nil,
        allowance: AllowanceStore = AllowanceStore(defaults: UserDefaults(suiteName: "preview") ?? .standard),
        store: StoreService = StoreService(),
        contentUpdater: ContentUpdater? = nil,
        makeListenDependencies: @escaping @MainActor (SettingsStore) -> ListenSessionModel.Dependencies
    ) {
        self.settings = settings
        self.entitlements = entitlements
        self.players = players
        self.questionSource = questionSource
        self.telemetry = telemetry ?? Telemetry(endpoint: nil, fileURL: nil, isEnabled: { false })
        self.allowance = allowance
        self.store = store
        self.contentUpdater = contentUpdater
        self.makeListenDependencies = makeListenDependencies
    }

    static func live() -> AppEnvironment {
        let settings = SettingsStore()
        let telemetry = Telemetry(endpoint: Telemetry.configuredEndpoint,
                                  isEnabled: { [weak settings] in settings?.settings.shareDiagnostics ?? false })
        let entitlements = EntitlementStore()
        let allowance = AllowanceStore()
        let store = StoreService()
        store.onPackBought = { [weak allowance] id in allowance?.creditPack(transactionID: id) }
        store.onSubscriptionChanged = { [weak entitlements] active in entitlements?.subscribed = active }
        let contentUpdater = ContentUpdater.live(telemetry: telemetry)
        let environment = AppEnvironment(
            settings: settings,
            entitlements: entitlements,
            players: PlayerStore.live(),
            questionSource: BundledContent.source(downloaded: contentUpdater?.preferredSet(), telemetry: telemetry),
            telemetry: telemetry,
            allowance: allowance,
            store: store,
            contentUpdater: contentUpdater,
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
        let sync = ProgressSync.live(allowance: allowance, players: environment.players)
        sync.start()
        environment.sync = sync
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

    /// TestFlight only (ADR-0027): back to a fresh install. Deletes the players and their
    /// progress, the questions used, packs credited, settings and the Basic test switch, here and
    /// in the iCloud and Keychain backup, so a reinstall doesn't bring them back. Purchases stay
    /// with the Apple ID (StoreKit).
    func resetAllData() {
        guard entitlements.isTestBuild else { return }
        sync?.eraseBackup()
        players.eraseAll()
        allowance.reset()
        settings.reset()
        entitlements.testerUnlock = false
        refreshAllowance()
    }

    var bank: QuestionBank? {
        if case .loaded(let bank) = content { return bank }
        return nil
    }

    /// Once per launch and whenever the app comes back: purchases, and the daily top-up.
    func refreshAllowance() {
        guard let bank else { return }
        // Anything already played before metering started is the family's.
        allowance.seed(with: players.learning(for: players.players).values.flatMap(\.cards.keys))
        allowance.appOpened(day: LearningDay.number(), freeTopics: bank.topics.filter(\.isFree))
    }

    func loadContent() async {
        guard bank == nil else { return }
        do {
            content = .loaded(try await questionSource.loadBank())
            refreshAllowance()
        } catch {
            content = .failed(String(describing: error))
            telemetry.record("content.loadFailed", ["error": String(describing: error)])
        }
    }

    /// Checks for newer questions (ADR-0031), at most every 12 hours. A new set replaces the bank
    /// for the next game; a game already playing keeps the bank it started with.
    func updateContent() async {
        guard let contentUpdater, bank != nil else { return }
        guard case .installed(let folder) = await contentUpdater.checkIfDue() else { return }
        guard let newBank = try? DirectoryQuestionSource(root: folder).loadBankSync(), !newBank.questions.isEmpty else {
            return
        }
        content = .loaded(newBank)
        refreshAllowance()
    }

    /// How many questions each the players would get today, planned exactly as the game would
    /// be (ADR-0022), without building the game's audio. nil if it can't be planned.
    func plannedEach(topics: [String], profiles: [PlayerProfile], length: SessionLength) -> (planned: Int, requested: Int)? {
        guard let bank, !profiles.isEmpty else { return nil }
        let s = settings.settings
        let config = SessionConfig(topics: topics, players: profiles.map(\.quizPlayer), length: length,
                                   includeTalkAbout: s.includeTalkAbout)
        let budget = allowance.budget(for: bank.topics.filter { topics.contains($0.id) }, bank: bank,
                                      hasBasic: entitlements.hasBasic, day: LearningDay.number())
        let session = QuizSession(bank: bank, config: config, learning: players.learning(for: players.players),
                                  budget: budget)
        return (session.plannedEach, session.requestedEach)
    }

    /// A Listen-mode session for the chosen players, taking turns, each with questions
    /// for their own age (ADR-0015).
    func makeListenSession(topics: [String], profiles: [PlayerProfile], length: SessionLength) -> ListenSessionModel? {
        guard let bank, !profiles.isEmpty else { return nil }
        let s = settings.settings
        let day = LearningDay.number()
        let hasBasic = entitlements.hasBasic
        let budget = allowance.budget(for: bank.topics.filter { topics.contains($0.id) }, bank: bank,
                                      hasBasic: hasBasic, day: day)
        let config = SessionConfig(topics: topics, players: profiles.map(\.quizPlayer), length: length,
                                   includeTalkAbout: s.includeTalkAbout)
        let model = ListenSessionModel(
            bank: bank, config: config, settings: s.listen, duckOthers: s.duckOthers,
            dependencies: makeListenDependencies(settings),
            answerMode: s.answerMode, mic: s.micPreference,
            // The whole family's boxes: absent players' recent questions can be shared, and
            // nobody gets a question someone else already had today (ADR-0016).
            learning: players.learning(for: players.players), lifetimeStats: players.stats(for: profiles),
            day: day,
            playerColors: Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0.colorHex) }),
            showScoreboard: s.showScoreboard, canFixScores: entitlements.canFixScores, budget: budget,
            variety: true)
        model.onFinish = { [weak players, weak allowance] summary in
            players?.record(summary)
            allowance?.charge(summary.asked, hasBasic: hasBasic, day: day)
        }
        model.onScoreAdjusted = { [weak players] playerID, change in players?.adjustPoints(for: playerID, by: change) }
        return model
    }
}
