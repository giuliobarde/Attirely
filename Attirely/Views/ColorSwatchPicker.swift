import SwiftUI

struct ColorSwatchPicker: View {
    let label: String
    @Binding var selection: String
    var allowsNone: Bool = false
    var aiOriginalValue: String? = nil

    private static let knownColors = [
        "Black", "White", "Gray", "Navy", "Blue", "Red", "Green",
        "Yellow", "Orange", "Pink", "Purple", "Brown", "Beige",
        "Cream", "Olive", "Teal", "Burgundy", "Maroon", "Tan",
        "Khaki", "Charcoal", "Coral", "Gold", "Silver", "Denim Blue"
    ]

    private var displayColors: [String] {
        var colors = Self.knownColors
        let normalized = selection.lowercased().trimmingCharacters(in: .whitespaces)
        let isKnown = colors.contains { $0.lowercased() == normalized }
        if !isKnown && !selection.isEmpty {
            colors.insert(selection, at: 0)
        }
        return colors
    }

    private let columns = [GridItem(.adaptive(minimum: 56))]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            LazyVGrid(columns: columns, spacing: 10) {
                if allowsNone {
                    noneCell
                }

                ForEach(displayColors, id: \.self) { color in
                    colorCell(color)
                }
            }

            if let original = aiOriginalValue, original != selection {
                Text("AI detected: \(original)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func colorCell(_ color: String) -> some View {
        let isSelected = selection.lowercased() == color.lowercased()
        return Button {
            selection = color
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(ColorMapping.color(for: color))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.champagne, lineWidth: 2.5)
                            .padding(-2)
                            .opacity(isSelected ? 1 : 0)
                    )

                Text(color)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Theme.primaryText : Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(.plain)
    }

    private var noneCell: some View {
        Button {
            selection = ""
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Theme.stone)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Theme.champagne, lineWidth: 2.5)
                            .padding(-2)
                            .opacity(selection.isEmpty ? 1 : 0)
                    )

                Text("None")
                    .font(.system(size: 9))
                    .foregroundStyle(selection.isEmpty ? Theme.primaryText : Theme.secondaryText)
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(.plain)
    }
}
