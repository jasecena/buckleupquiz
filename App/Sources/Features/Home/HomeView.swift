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
    @State private var lockedTopic: Topic?
    @State private var showSettings = false
    @State private var setup: SetupRequest?
    @State private var activeSession: ListenSessionModel?
    @State private var notice: String?
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
                            if unlocked { play(topic) } else { lockedTopic = topic }
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
        .sheet(item: $lockedTopic) { topic in
            FamilyPassTeaser(topic: topic)
                .presentationDetents([.medium])
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
    private func play(_ topic: Topic?) {
        guard !selected.isEmpty else {
            setup = SetupRequest(startTopic: .some(topic))
            return
        }
        let family = playerStore.learning(for: playerStore.players)
        let day = LearningDay.number()
        func playable(_ topic: Topic) -> [PlayerProfile] {
            let selector = QuestionSelector(bank: bank, topics: [topic.id],
                                            includeTalkAbout: settingsStore.settings.includeTalkAbout)
            return selected.filter { selector.availableCount(for: $0.quizPlayer, family: family, day: day) > 0 }
        }

        let chosen: Topic
        if let topic {
            chosen = topic
        } else {
            // A random topic where everyone has something to play, else where anyone does.
            let open = topics.filter(entitlements.isUnlocked)
            let forAll = open.filter { playable($0).count == selected.count }
            guard let pick = (forAll.isEmpty ? open.filter { !playable($0).isEmpty } : forAll).randomElement() else {
                notice = "That's everything for today. Come back tomorrow for more!"
                return
            }
            chosen = pick
        }
        let players = playable(chosen)
        guard !players.isEmpty else {
            notice = "No more \(chosen.name) questions today for \(ListFormatter.localizedString(byJoining: selected.map(\.name))). Try another topic!"
            return
        }
        let length = settingsStore.settings.lastSessionLength
        Task {
            // Voice answers ask for the microphone once, the first time they're used (ADR-0018).
            if settingsStore.settings.answerMode == .voice, !SystemSpeechListener.hasPermission,
               !(await SystemSpeechListener.requestPermission()) {
                settingsStore.settings.answerMode = .listen
            }
            activeSession = environment.makeListenSession(topics: [chosen.id], profiles: players, length: length)
        }
    }

    private func normaliseSelection() {
        // Forget players that were removed; pre-select a lone player.
        let known = Set(playerStore.players.map(\.id.uuidString))
        settingsStore.settings.selectedPlayerIDs.removeAll { !known.contains($0) }
        if playerStore.players.count == 1, let only = playerStore.players.first { settingsStore.select(only) }
        if !entitlements.isAvailable(settingsStore.settings.lastSessionLength) {
            settingsStore.settings.lastSessionLength = .questions(10)
        }
    }
}

/// Placeholder until the StoreKit paywall lands in M6.
private struct FamilyPassTeaser: View {
    let topic: Topic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("\(topic.name) is part of the Family Pass")
                .font(Theme.title)
                .multilineTextAlignment(.center)
            Text("The Family Pass unlocks every topic, Endless mode, players and voice answers.")
                .font(Theme.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("OK") { dismiss() }
                .buttonStyle(BigButtonStyle())
        }
        .padding(32)
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
}
#endif
