import SwiftUI

/// Bright, high-contrast colours and big rounded type (FEATURES §0).
enum Theme {
    static let accent = Color.accentColor
    static let background = Color("LaunchBackground")

    static let hero = Font.system(size: 34, weight: .heavy, design: .rounded)
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
