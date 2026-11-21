import SwiftUI

/// "Ask a grown-up": a sum a young child can't do in their head, required before any purchase
/// or link out of the app (Kids Category, App Review 1.3; FEATURES §5).
struct ParentalGate<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var passed = false
    @State private var question = Self.makeQuestion()
    @State private var answer = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        if passed {
            content()
        } else {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                Text("Grown-ups only").font(Theme.title)
                Text("What is \(question.a) × \(question.b)?")
                    .font(Theme.headline)
                TextField("Answer", text: $answer)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.title)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
                    .focused($focused)
                if wrong {
                    Text("Not quite. Here's another one.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Continue") { check() }
                    .buttonStyle(BigButtonStyle())
                    .disabled(answer.isEmpty)
            }
            .padding(32)
            .onAppear { focused = true }
        }
    }

    private func check() {
        if Int(answer) == question.a * question.b {
            passed = true
        } else {
            wrong = true
            answer = ""
            question = Self.makeQuestion()
        }
    }

    private static func makeQuestion() -> (a: Int, b: Int) {
        (Int.random(in: 12...19), Int.random(in: 3...9))
    }
}
