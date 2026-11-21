import QuizCore
import SwiftUI

/// Pick who's playing and how long, then start (ADR-0015).
/// There is no age picker: each player's age decides their questions.
struct SessionSetupView: View {
    let topic: Topic
    let bank: QuestionBank
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PlayerStore.self) private var playerStore
    @State private var activeSession: ListenSessionModel?
    @State private var editing: PlayerEditorTarget?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        @Bindable var store = settingsStore
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label(topic.name, systemImage: topic.symbol)
                    .font(Theme.hero)
                    .foregroundStyle(Color(hex: topic.color))

                section("Who's playing?") {
                    if playerStore.players.isEmpty {
                        Text("Add the kids who are playing. Their age decides which questions they get.")
                            .font(Theme.body)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(playerStore.players) { profile in
                            Button { toggle(profile) } label: {
                                PlayerChip(name: profile.name, age: profile.currentAge(), colorHex: profile.colorHex,
                                           isSelected: isSelected(profile), note: note(for: profile))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = .edit(profile) }
                            }
                        }
                        if playerStore.canAddMore {
                            Button { editing = .new } label: { AddPlayerChip() }
                                .buttonStyle(.plain)
                        }
                    }
                }

                section("How many questions?") {
                    ForEach(SessionLength.presets, id: \.self) { length in
                        let available = entitlements.isAvailable(length)
                        choice(length.displayName, detail: available ? nil : "Family Pass",
                               selected: store.settings.lastSessionLength == length) {
                            store.settings.lastSessionLength = length
                        }
                        .disabled(!available)
                    }
                }

                Button {
                    startSession()
                } label: {
                    Label(startTitle, systemImage: "play.fill")
                }
                .buttonStyle(BigButtonStyle(color: Color(hex: topic.color)))
                .disabled(playable.isEmpty)
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: normaliseSelection)
        .sheet(item: $editing) { target in
            PlayerEditorView(target: target) { saved in
                // A newly added player is playing straight away.
                if case .new = target { select(saved) }
            }
        }
        .fullScreenCover(item: $activeSession) { model in
            QuizView(model: model)
        }
    }

    // MARK: Selection

    private var selected: [PlayerProfile] {
        playerStore.players.filter(isSelected)
    }

    /// Selected players who have questions in this topic for their age.
    private var playable: [PlayerProfile] {
        selected.filter { questionCount(for: $0) > 0 }
    }

    private var startTitle: String {
        if selected.isEmpty { return "Pick who's playing" }
        if playable.isEmpty { return "No questions for these ages yet" }
        return "Start"
    }

    private func isSelected(_ profile: PlayerProfile) -> Bool {
        settingsStore.settings.selectedPlayerIDs.contains(profile.id.uuidString)
    }

    private func toggle(_ profile: PlayerProfile) {
        let id = profile.id.uuidString
        if let index = settingsStore.settings.selectedPlayerIDs.firstIndex(of: id) {
            settingsStore.settings.selectedPlayerIDs.remove(at: index)
        } else {
            settingsStore.settings.selectedPlayerIDs.append(id)
        }
    }

    private func select(_ profile: PlayerProfile) {
        if !isSelected(profile) { settingsStore.settings.selectedPlayerIDs.append(profile.id.uuidString) }
    }

    private func questionCount(for profile: PlayerProfile) -> Int {
        bank.questionCount(topic: topic.id, ageBand: profile.ageBand)
    }

    private func note(for profile: PlayerProfile) -> String? {
        questionCount(for: profile) == 0 ? "Age \(profile.currentAge()) · no questions yet" : nil
    }

    private func normaliseSelection() {
        // Forget players that were removed; pre-select a lone player.
        let known = Set(playerStore.players.map(\.id.uuidString))
        settingsStore.settings.selectedPlayerIDs.removeAll { !known.contains($0) }
        if playerStore.players.count == 1, let only = playerStore.players.first { select(only) }
        if !entitlements.isAvailable(settingsStore.settings.lastSessionLength) {
            settingsStore.settings.lastSessionLength = .questions(10)
        }
    }

    private func startSession() {
        activeSession = environment.makeListenSession(
            topics: [topic.id], profiles: playable, length: settingsStore.settings.lastSessionLength)
    }

    // MARK: Building blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.title)
            content()
        }
    }

    private func choice(_ title: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let detail { Text(detail).font(Theme.body).opacity(0.8) }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            }
        }
        .buttonStyle(BigButtonStyle(color: Color(hex: topic.color), prominent: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ListenSessionModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
