import SwiftUI

/// Think-time countdown (FEATURES §2.2).
struct CountdownRing: View {
    let remaining: Double
    let total: Double
    var color: Color = Theme.accent

    var body: some View {
        let progress = total > 0 ? remaining / total : 0
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
            Text("\(Int(remaining.rounded(.up)))")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
    }
}
