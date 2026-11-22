import SwiftUI

/// Bright, high-contrast colours and big rounded type (FEATURES §0).
enum Theme {
    static let accent = Color.accentColor
    static let background = Color("LaunchBackground")

    /// Every font follows the reader's text size (Dynamic Type).
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .heavy)
    static let title = Font.system(.title, design: .rounded, weight: .bold)
    static let headline = Font.system(.title3, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .rounded)
    static let question = Font.system(.title2, design: .rounded, weight: .bold)

    static let corner: CGFloat = 24
}

extension Color {
    /// "#RRGGBB" from the topic catalogue.
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Side by side, or stacked at the largest accessibility text sizes so nothing is cut off.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: spacing, content: content)
        } else {
            HStack(spacing: spacing, content: content)
        }
    }
}

/// Large, thumb-friendly button used for primary actions and quiz controls.
struct BigButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal)
            .foregroundStyle(prominent ? Color.white : color)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(prominent ? color : color.opacity(0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
