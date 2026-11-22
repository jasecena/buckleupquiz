import SwiftUI

/// "Ask a grown-up", required before any purchase or link out of the app (Kids Category, App
/// Review 1.3; FEATURES §5). Three numbers written as words ("seven, two, nine") to type as
/// digits: quick for any adult, hard for a young child. It replaced a sum like 17 × 8, which
/// was too hard for a parent in the car (product decision, 2026-11-22).
struct ParentalGate<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var passed = false
    @State private var digits = Self.makeDigits()
    @State private var answer = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        if passed {
            content()
        } else {
            ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Grown-ups only").font(Theme.title)
                Text("Type these numbers:")
                    .font(Theme.body)
                    .foregroundStyle(.secondary)
                Text(digits.map { Self.words[$0] }.joined(separator: ", "))
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
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { focused = true }
        }
    }

    private func check() {
        if answer.filter(\.isNumber) == digits.map(String.init).joined() {
            passed = true
        } else {
            wrong = true
            answer = ""
            digits = Self.makeDigits()
        }
    }

    private static let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]

    private static func makeDigits() -> [Int] {
        (0..<3).map { _ in Int.random(in: 1...9) }
    }
}
