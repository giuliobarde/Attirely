import SwiftUI

struct TagChipView: View {
    let tag: Tag
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
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
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var chipBackground: Color {
        if tag.colorHex != nil {
            return tag.tagColor.opacity(0.25)
        }
        return isSelected ? Theme.pillActiveBg : Theme.tagBackground
    }

    private var chipForeground: Color {
        if tag.colorHex != nil {
            return Theme.primaryText
        }
        return isSelected ? Theme.champagne : Theme.tagText
    }
}
