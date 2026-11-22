import SwiftUI

/// Three cards shown once, before the first game (product decision, 2026-11-22): how the game
/// works, "say the letter" (ADR-0026), and the phone on screen in a cradle (ADR-0029, ADR-0008).
/// The first real game is the demo. Then Home carries on as before ("Who's playing?").
struct WelcomeView: View {
    var onFinish: () -> Void
    @State private var page = 0

    struct Card: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
    }

    static let cards = [
        Card(id: 0, symbol: "car.fill", title: "A quiz for the car",
             text: "BuckleUp Quiz reads each question out loud, and the kids answer out loud. "
                 + "Nobody needs to look at the screen."),
        Card(id: 1, symbol: "mic.fill", title: "Say the letter",
             text: "Each question has answers A, B and C, or true and false. Say the letter as soon as "
                 + "you know it. You can also say \"skip\", \"repeat\" or \"pause\"."),
        Card(id: 2, symbol: "iphone.gen3", title: "Phone in a cradle, app open",
             text: "Answers are only heard while the app is on screen, so the screen stays on during a "
                 + "game. Plug it in for long trips. Some cars show a phone-call screen while the "
                 + "microphone is on. That's normal. If the car is too noisy, Settings → Answers → "
                 + "Just listen reads the answers out instead."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(Self.cards) { card in
                    // Scrolls when large text makes a card taller than the screen.
                    ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: card.symbol)
                            .font(.system(size: 72))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text(card.title)
                            .font(Theme.title)
                            .multilineTextAlignment(.center)
                        Text(card.text)
                            .font(Theme.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .tag(card.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page < Self.cards.count - 1 ? "Next" : "Let's go!") {
                if page < Self.cards.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(BigButtonStyle())
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Theme.background.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    WelcomeView {}
}
#endif
