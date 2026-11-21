import SwiftUI

/// A big, tappable name badge used in "Who's playing?" and the players list.
struct PlayerChip: View {
    let name: String
    let age: Int
    let colorHex: String
    var isSelected = false
    var note: String?

    var body: some View {
        let color = Color(hex: colorHex)
        HStack(spacing: 12) {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .frame(width: 48, height: 48)
                .background(Circle().fill(isSelected ? Color.white.opacity(0.25) : color))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.headline).lineLimit(1)
                Text(note ?? "Age \(age)").font(.system(.caption, design: .rounded, weight: .medium)).opacity(0.85)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill").font(.title2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(isSelected ? color : color.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The "+ Add player" tile.
struct AddPlayerChip: View {
    var body: some View {
        Label("Add player", systemImage: "plus.circle.fill")
            .font(Theme.headline)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
    }
}
