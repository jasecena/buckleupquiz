import QuizCore
import SwiftUI

/// Grid of big topic tiles (FEATURES §2.1).
struct HomeView: View {
    let bank: QuestionBank
    @Environment(EntitlementStore.self) private var entitlements
    @State private var lockedTopic: Topic?
    @State private var showSettings = false
    @State private var showPlayers = false

    private var topics: [Topic] { bank.topics.filter { bank.questionCount(topic: $0.id) > 0 } }
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a topic")
                    .font(Theme.hero)
                Text("Questions are read aloud, so eyes can stay on the road.")
                    .font(Theme.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(topics) { topic in
                    let unlocked = entitlements.isUnlocked(topic)
                    let tile = TopicTile(topic: topic, questionCount: bank.questionCount(topic: topic.id),
                                         isLocked: !unlocked)
                    if unlocked {
                        NavigationLink(value: topic) { tile }
                            .buttonStyle(.plain)
                    } else {
                        Button { lockedTopic = topic } label: { tile }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("BuckleUp Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Topic.self) { topic in
            SessionSetupView(topic: topic, bank: bank)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showPlayers = true } label: {
                    Label("Players", systemImage: "person.2.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPlayers) { PlayersView() }
        .sheet(item: $lockedTopic) { topic in
            FamilyPassTeaser(topic: topic)
                .presentationDetents([.medium])
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
    NavigationStack {
        HomeView(bank: .preview)
    }
    .environment(EntitlementStore())
    .environment(PlayerStore.inMemory())
    .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
}
#endif
