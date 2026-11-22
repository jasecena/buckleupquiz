import QuizCore
import SwiftUI

struct TopicTile: View {
    let topic: Topic
    let questionCount: Int
    let isLocked: Bool

    var body: some View {
        let color = Color(hex: topic.color)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: topic.symbol)
                    .font(.system(size: 34, weight: .bold))
                    .accessibilityHidden(true)
                Spacer()
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.headline)
                        .accessibilityLabel("Locked")
                }
            }
            Spacer(minLength: 0)
            Text(topic.name)
                .font(Theme.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("\(questionCount) questions")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(color.gradient)
        )
        .opacity(isLocked ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
