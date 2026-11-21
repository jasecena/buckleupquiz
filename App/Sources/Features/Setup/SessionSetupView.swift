import QuizCore
import SwiftUI

/// Pick an age band and session length, then start (FEATURES §2.1–2.2).
struct SessionSetupView: View {
    let topic: Topic
    let bank: QuestionBank
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(EntitlementStore.self) private var entitlements
    @State private var activeSession: ListenSessionModel?

    var body: some View {
        @Bindable var store = settingsStore
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label(topic.name, systemImage: topic.symbol)
                    .font(Theme.hero)
                    .foregroundStyle(Color(hex: topic.color))

                section("How old are the players?") {
                    ForEach(topic.ageBands, id: \.self) { band in
                        choice(band.displayName,
                               detail: "\(bank.questionCount(topic: topic.id, ageBand: band)) questions",
                               selected: store.settings.lastAgeBand == band) {
                            store.settings.lastAgeBand = band
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
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(BigButtonStyle(color: Color(hex: topic.color)))
                .disabled(selectedBandIsEmpty)
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: normaliseSelection)
        .fullScreenCover(item: $activeSession) { model in
            QuizView(model: model)
        }
    }

    private var selectedBandIsEmpty: Bool {
        bank.questionCount(topic: topic.id, ageBand: settingsStore.settings.lastAgeBand) == 0
    }

    private func normaliseSelection() {
        if !topic.ageBands.contains(settingsStore.settings.lastAgeBand), let first = topic.ageBands.first {
            settingsStore.settings.lastAgeBand = first
        }
        if !entitlements.isAvailable(settingsStore.settings.lastSessionLength) {
            settingsStore.settings.lastSessionLength = .questions(10)
        }
    }

    private func startSession() {
        let s = settingsStore.settings
        activeSession = environment.makeListenSession(topics: [topic.id], ageBand: s.lastAgeBand,
                                                      length: s.lastSessionLength)
    }

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
