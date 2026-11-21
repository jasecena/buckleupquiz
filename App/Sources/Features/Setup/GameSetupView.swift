import QuizCore
import SwiftUI

/// "Who's playing?" and "How many questions?" (ADR-0015, ADR-0017).
/// Shown once before the first game, and afterwards only when someone taps Change:
/// the choice is remembered, so most games start with a single tap on Home.
struct GameSetupView: View {
    /// When set, the main button reads "Let's go!" and the game starts on close.
    var startsGame = false
    var onStart: () -> Void = {}

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PlayerStore.self) private var playerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PlayerEditorTarget?
    @State private var managePlayers = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        @Bindable var store = settingsStore
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("Who's playing?") {
                        if playerStore.players.isEmpty {
                            Text("Add the kids who are playing. Their age decides which questions they get.")
                                .font(Theme.body)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(playerStore.players) { profile in
                                Button { settingsStore.toggle(profile) } label: {
                                    PlayerChip(name: profile.name, age: profile.currentAge(), colorHex: profile.colorHex,
                                               isSelected: settingsStore.isSelected(profile))
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
                        dismiss()
                        if startsGame { onStart() }
                    } label: {
                        Label(startsGame ? "Let's go!" : "Done", systemImage: startsGame ? "play.fill" : "checkmark")
                    }
                    .buttonStyle(BigButtonStyle())
                    .disabled(selectedCount == 0)
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Game setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit players") { managePlayers = true }
                        .disabled(playerStore.players.isEmpty)
                }
            }
            .sheet(isPresented: $managePlayers) { PlayersView() }
            .sheet(item: $editing) { target in
                PlayerEditorView(target: target) { saved in
                    // A newly added player is playing straight away.
                    if case .new = target { settingsStore.select(saved) }
                }
            }
        }
    }

    private var selectedCount: Int { playerStore.players.filter(settingsStore.isSelected).count }

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
        .buttonStyle(BigButtonStyle(prominent: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension SettingsStore {
    func isSelected(_ profile: PlayerProfile) -> Bool {
        settings.selectedPlayerIDs.contains(profile.id.uuidString)
    }

    func toggle(_ profile: PlayerProfile) {
        let id = profile.id.uuidString
        if let index = settings.selectedPlayerIDs.firstIndex(of: id) {
            settings.selectedPlayerIDs.remove(at: index)
        } else {
            settings.selectedPlayerIDs.append(id)
        }
    }

    func select(_ profile: PlayerProfile) {
        if !isSelected(profile) { settings.selectedPlayerIDs.append(profile.id.uuidString) }
    }
}
