import SwiftUI

struct ClothingItemCard: View {
    let item: any ClothingItemDisplayable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: type + category pill
            HStack(alignment: .firstTextBaseline) {
                Text(item.type)
                    .font(.headline)

                Spacer()

                Text(item.category)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            // Color row
            HStack(spacing: 6) {
                Circle()
                    .fill(ColorMapping.color(for: item.primaryColor))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))

                Text(item.primaryColor)
                    .font(.subheadline)

                if let secondary = item.secondaryColor {
                    Text("/")
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(ColorMapping.color(for: secondary))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    Text(secondary)
                        .font(.subheadline)
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
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Description
            Text(item.displayDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func attributeRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
