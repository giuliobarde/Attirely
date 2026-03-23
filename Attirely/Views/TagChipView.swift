import SwiftUI

struct TagChipView: View {
    let tag: Tag
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button {
                onTap()
            } label: {
                chipLabel
            }
            .buttonStyle(.plain)
        } else {
            chipLabel
                .allowsHitTesting(false)
        }
    }

    private var chipLabel: some View {
        Text(tag.name)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(chipBackground)
            .foregroundStyle(chipForeground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isSelected ? chipForeground.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
            )
    }

    private var chipBackground: Color {
        if let accent = tag.resolvedAccentColor {
            return accent.opacity(0.28)
        }
        return isSelected ? Theme.pillActiveBg : Theme.tagBackground
    }

    private var chipForeground: Color {
        if tag.resolvedAccentColor != nil {
            return Theme.primaryText
        }
        return isSelected ? Theme.champagne : Theme.tagText
    }
}
