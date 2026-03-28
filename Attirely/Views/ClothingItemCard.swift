import SwiftUI

struct ClothingItemCard: View {
    let item: any ClothingItemDisplayable
    var sourceImageIndices: [Int]? = nil
    var totalImageCount: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: type + category pill
            HStack(alignment: .firstTextBaseline) {
                Text(item.type)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)

                Spacer()

                Text(item.category)
                    .themePill()
            }

            // Source image badges (multi-image scan only)
            if let indices = sourceImageIndices, totalImageCount > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Found in")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(indices, id: \.self) { index in
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.champagne)
                            .frame(width: 18, height: 18)
                            .background(Theme.champagne.opacity(0.15))
                            .clipShape(Circle())
                    }
                    Text("of \(totalImageCount) photos")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            // Color row
            HStack(spacing: 6) {
                Circle()
                    .fill(ColorMapping.color(for: item.primaryColor))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))

                Text(item.primaryColor)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)

                if let secondary = item.secondaryColor {
                    Text("/")
                        .foregroundStyle(Theme.secondaryText)
                    Circle()
                        .fill(ColorMapping.color(for: secondary))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                }
            }

            // Attributes grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], alignment: .leading, spacing: 6) {
                attributeRow("Pattern", item.pattern)
                attributeRow("Fabric", item.fabricEstimate)
                attributeRow("Weight", item.weight)
                attributeRow("Formality", item.formality)
                attributeRow("Statement", item.statementLevel)
                if let fit = item.fit {
                    attributeRow("Fit", fit)
                }
            }

            // Season tags
            HStack(spacing: 6) {
                ForEach(item.season, id: \.self) { season in
                    Text(season)
                        .themeTag()
                }
            }

            // Description
            Text(item.displayDescription)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .themeCard()
    }

    private func attributeRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)
        }
    }
}
