import QuizCore
import StoreKit
import SwiftUI

/// More questions (ADR-0022): BuckleUp Basic or a 50-question pack. Always shown behind the
/// parental gate.
struct PlansView: View {
    /// Why it was opened, e.g. "You're out of questions for today."
    var reason: String?
    @Environment(StoreService.self) private var store
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(AllowanceStore.self) private var allowance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let reason {
                        Text(reason).font(Theme.headline)
                    }
                    basicCard
                    packCard
                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Restore purchases") { Task { await store.restore() } }
                        Text("BuckleUp Basic renews every month until you cancel. Cancel anytime in Settings › your name › Subscriptions. Question packs are a one-time purchase and never expire.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            Link("Privacy Policy", destination: URL(string: "https://buckleupquiz.com/privacy.html")!)
                        }
                        .font(.footnote)
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("More questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .disabled(store.isBusy)
            .task { await store.loadProducts() }
        }
    }

    private var basicCard: some View {
        card(
            title: "BuckleUp Basic",
            price: store.basic.map { "\($0.displayPrice) a month" } ?? "A$4.99 a month",
            lines: [
                "All 10 topics",
                "\(AllowanceStore.basicDaily) new questions each day you open the app",
                "Up to \(PlayerStore.maxPlayers) players",
                "Fix scores after a game",
                "Cancel anytime",
            ],
            actionTitle: entitlements.hasBasic ? nil : "Subscribe",
            footnote: entitlements.hasBasic ? "You have BuckleUp Basic. Thank you!" : nil
        ) {
            Task { if await store.buy(StoreService.basicMonthly) { dismiss() } }
        }
    }

    private var packCard: some View {
        card(
            title: "\(AllowanceStore.packSize) more questions",
            price: store.pack.map { "\($0.displayPrice), one time" } ?? "A$0.99, one time",
            lines: ["For any topic you can play", "Never expire"],
            actionTitle: "Buy",
            footnote: allowance.state.packCredits > 0 ? "\(allowance.state.packCredits) bought questions left" : nil
        ) {
            Task { _ = await store.buy(StoreService.questionPack) }
        }
    }

    private func card(title: String, price: String, lines: [String], actionTitle: String?,
                      footnote: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.title)
            Text(price).font(Theme.headline).foregroundStyle(Theme.accent)
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill").font(Theme.body)
            }
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
            }
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(BigButtonStyle())
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.accent.opacity(0.1)))
    }
}

/// The plans screen behind the parental gate, ready to present as a sheet.
struct GetMoreQuestionsSheet: View {
    var reason: String?
    var body: some View {
        ParentalGate { PlansView(reason: reason) }
    }
}
