import QuizCore
import SwiftUI

/// Home: one tap to play (ADR-0017). Who's playing and how long are remembered from last
/// time, so "Play" starts straight away on a random topic, and tapping a topic starts that
/// topic. Setup only appears before the very first game, or when someone taps Change.
struct HomeView: View {
    let bank: QuestionBank
    @Environment(AppEnvironment.self) private var environment
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PlayerStore.self) private var playerStore
    @Environment(SettingsStore.self) private var settingsStore
    @State private var showSettings = false
    @State private var setup: SetupRequest?
    @State private var activeSession: ListenSessionModel?
    @State private var notice: String?
    /// Fewer questions left today than the game asked for (ADR-0022).
    @State private var shortGame: ShortGame?
    @State private var getMore: GetMore?

    private struct ShortGame: Identifiable {
        let id = UUID()
        let topic: Topic
        let each: Int
        /// 0–2 each: the game can't start today.
        var blocked: Bool { each <= 2 }
    }

    private struct GetMore: Identifiable {
        let id = UUID()
        let reason: String?
    }
    /// Set when setup's "Let's go!" is tapped; the game starts once the sheet has closed.
    @State private var startAfterSetup: Topic??

    /// What to start once setup is done: a topic, or nil for a random one.
    private struct SetupRequest: Identifiable {
        let id = UUID()
        let startTopic: Topic??
    }

    private var topics: [Topic] { bank.topics.filter { bank.questionCount(topic: $0.id) > 0 } }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                whoIsPlaying
                Button { play(nil) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(Theme.title)
                }
                .buttonStyle(BigButtonStyle())
                .accessibilityHint("Starts a game on a random topic")

                Text("Or pick a topic")
                    .font(Theme.headline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(topics) { topic in
                        let unlocked = entitlements.isUnlocked(topic)
                        Button {
                            if unlocked {
                                play(topic)
                            } else {
                                getMore = GetMore(reason: "\(topic.name) is part of BuckleUp Basic.")
                            }
                        } label: {
                            TopicTile(topic: topic, questionCount: bank.questionCount(topic: topic.id),
                                      isLocked: !unlocked)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("BuckleUp Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
        }
        .onAppear(perform: normaliseSelection)
        .onChange(of: entitlements.hasBasic) { normaliseSelection() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $setup, onDismiss: {
            if let topic = startAfterSetup {
                startAfterSetup = nil
                play(topic)
            }
        }) { request in
            GameSetupView(startsGame: request.startTopic != nil) {
                startAfterSetup = request.startTopic
            }
        }
        .sheet(item: $getMore) { request in
            GetMoreQuestionsSheet(reason: request.reason)
        }
        .alert(shortGame?.blocked == true ? "You're out of questions for today" : "Almost out of questions for today",
               isPresented: Binding(get: { shortGame != nil }, set: { if !$0 { shortGame = nil } }),
               presenting: shortGame) { short in
            if short.blocked {
                Button("OK", role: .cancel) {}
            } else {
                Button("Play \(short.each) each") { start(short.topic) }
                Button("Not now", role: .cancel) {}
            }
            Button("Get more questions") {
                getMore = GetMore(reason: short.blocked ? "You're out of \(short.topic.name) questions for today." : nil)
            }
        } message: { short in
            Text(short.blocked
                 ? "New \(short.topic.name) questions come back tomorrow. Or get more now."
                 : "There are \(short.each) new \(short.topic.name) questions each left for today.")
        }
        .fullScreenCover(item: $activeSession) { model in
            QuizView(model: model)
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Who's playing

    private var selected: [PlayerProfile] { playerStore.players.filter(settingsStore.isSelected) }

    private var whoIsPlaying: some View {
        Button { setup = SetupRequest(startTopic: nil) } label: {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(selected.prefix(4)) { profile in
                        Text(String(profile.name.prefix(1)).uppercased())
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(hex: profile.colorHex)))
                            .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                            .foregroundStyle(.white)
                    }
                    if selected.isEmpty {
                        Image(systemName: "person.2.fill").font(.title2).frame(width: 40, height: 40)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.isEmpty ? "Who's playing?" : ListFormatter.localizedString(byJoining: selected.map(\.name)))
                        .font(Theme.headline)
                        .lineLimit(1)
                    Text(settingsStore.settings.lastSessionLength.displayName)
                        .font(Theme.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Change").font(Theme.body.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.accent.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected.isEmpty ? "Choose who's playing" : "Playing: \(selected.map(\.name).joined(separator: ", ")). Change")
    }

    // MARK: Starting a game

    /// Starts straight away when players are already chosen; otherwise asks once first.
    /// Every game is planned before it starts (ADR-0022): if there aren't enough new questions
    /// left today, the family is told before anyone starts.
    private func play(_ topic: Topic?) {
        guard !selected.isEmpty else {
            setup = SetupRequest(startTopic: .some(topic))
            return
        }
        let length = settingsStore.settings.lastSessionLength
        func plan(_ topic: Topic) -> (planned: Int, requested: Int) {
            environment.plannedEach(topics: [topic.id], profiles: selected, length: length) ?? (0, 0)
        }
        let chosen: Topic
        if let topic {
            chosen = topic
        } else {
            // A random topic with a full game today, else the one with the most left.
            let planned = topics.filter(entitlements.isUnlocked).map { ($0, plan($0)) }
            let full = planned.filter { $0.1.planned >= min($0.1.requested, SessionLength.minimumEach) }
            guard let pick = full.randomElement() ?? planned.max(by: { $0.1.planned < $1.1.planned }) else { return }
            chosen = pick.0
        }
        let (each, requested) = plan(chosen)
        if each < requested, each < SessionLength.minimumEach {
            shortGame = ShortGame(topic: chosen, each: each)
        } else {
            start(chosen)
        }
    }

    private func start(_ topic: Topic) {
        let length = settingsStore.settings.lastSessionLength
        let players = selected
        Task {
            // Voice answers ask for the microphone once, the first time they're used (ADR-0018).
            if settingsStore.settings.answerMode == .voice, !SystemSpeechListener.hasPermission,
               !(await SystemSpeechListener.requestPermission()) {
                settingsStore.settings.answerMode = .listen
            }
            launch(topic, players: players, length: length)
        }
    }

    /// Starts a game, and lets it start the next one with the same topic, players and length
    /// ("new game" out loud, or "Play again"), when there are enough questions left today.
    private func launch(_ topic: Topic, players: [PlayerProfile], length: SessionLength) {
        guard let model = environment.makeListenSession(topics: [topic.id], profiles: players, length: length) else {
            return
        }
        model.playAgain = .init(
            isAvailable: { [environment] in
                guard let plan = environment.plannedEach(topics: [topic.id], profiles: players, length: length) else {
                    return false
                }
                // Same rule as starting from the topic grid: a short game needs a warning first.
                return plan.planned > 0 && !(plan.planned < plan.requested && plan.planned < SessionLength.minimumEach)
            },
            start: { launch(topic, players: players, length: length) })
        activeSession = model
    }

    private func normaliseSelection() {
        // Forget players that were removed; pre-select a lone player.
        let known = Set(playerStore.players.map(\.id.uuidString))
        settingsStore.settings.selectedPlayerIDs.removeAll { !known.contains($0) }
        if playerStore.players.count == 1, let only = playerStore.players.first { settingsStore.select(only) }
        // Free games have up to 2 players: keep the first ones picked.
        let selected = playerStore.players.filter(settingsStore.isSelected).map(\.id.uuidString)
        if selected.count > entitlements.playersPerGame {
            let keep = Set(selected.prefix(entitlements.playersPerGame))
            settingsStore.settings.selectedPlayerIDs.removeAll { !keep.contains($0) }
        }
        // Lengths are questions each now (ADR-0022): anything else goes back to 5 each.
        let length = settingsStore.settings.lastSessionLength
        if !SessionLength.presets.contains(length) {
            settingsStore.settings.lastSessionLength = .questions(5)
        }
    }
}

#if DEBUG
#Preview {
    let environment = AppEnvironment.live()
    NavigationStack {
        HomeView(bank: .preview)
    }
    .environment(environment)
    .environment(environment.entitlements)
    .environment(environment.players)
    .environment(environment.settings)
    .environment(environment.telemetry)
    .environment(environment.allowance)
    .environment(environment.store)
}
#endif
