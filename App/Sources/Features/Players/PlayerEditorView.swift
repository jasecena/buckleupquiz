import QuizCore
import SwiftUI

/// What the editor sheet is editing.
enum PlayerEditorTarget: Identifiable {
    case new
    case edit(PlayerProfile)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let profile): profile.id.uuidString
        }
    }
}

/// Add or edit a family member: name, age and colour (ADR-0015).
struct PlayerEditorView: View {
    let target: PlayerEditorTarget
    /// Called with the saved profile (new or edited).
    var onSave: (PlayerProfile) -> Void = { _ in }

    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var age = 7
    @State private var colorHex = PlayerStore.palette[0]
    @State private var confirmDelete = false

    private var existing: PlayerProfile? {
        if case .edit(let profile) = target { return profile }
        return nil
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First name", text: $name)
                        .font(Theme.headline)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                }
                Section {
                    Picker("Age", selection: $age) {
                        ForEach(PlayerStore.ageRange, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                } header: {
                    Text("Age")
                } footer: {
                    Text("Questions are picked for \(AgeBand(age: age).displayName.lowercased()). The age goes up by itself each year.")
                }
                Section("Colour") {
                    HStack(spacing: 12) {
                        ForEach(PlayerStore.palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if hex == colorHex {
                                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hex == colorHex ? "Selected colour" : "Colour")
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Button("Remove player", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New player" : "Edit player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Remove \(existing?.name ?? "player")?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let existing {
            name = existing.name
            age = existing.currentAge().clamped(to: PlayerStore.ageRange)
            colorHex = existing.colorHex
        } else {
            colorHex = store.nextColor
        }
    }

    private func save() {
        if let existing {
            store.update(existing, name: trimmedName, age: age, colorHex: colorHex)
            onSave(existing)
        } else if let created = store.add(name: trimmedName, age: age, colorHex: colorHex) {
            onSave(created)
        }
        dismiss()
    }
}
