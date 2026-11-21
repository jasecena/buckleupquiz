import SwiftUI

/// Manage the family's players (from Game setup → Edit players).
struct PlayersView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PlayerEditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Add each child who plays. Their age decides which questions they get.")
                        .font(Theme.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(store.players) { profile in
                        Button { editing = .edit(profile) } label: {
                            PlayerChip(name: profile.name, age: profile.currentAge(), colorHex: profile.colorHex)
                        }
                        .buttonStyle(.plain)
                    }
                    if store.canAddMore {
                        Button { editing = .new } label: { AddPlayerChip() }
                            .buttonStyle(.plain)
                    } else {
                        Text("Up to \(PlayerStore.maxPlayers) players.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
                PlayerEditorView(target: target)
            }
        }
    }
}
