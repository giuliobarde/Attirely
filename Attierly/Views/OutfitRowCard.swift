import SwiftUI

struct OutfitRowCard: View {
    let outfit: Outfit
    let onFavoriteToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name + badges
            HStack(alignment: .firstTextBaseline) {
                Text(outfit.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if outfit.isAIGenerated {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }

                Button {
                    onFavoriteToggle()
                } label: {
                    Image(systemName: outfit.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(outfit.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Occasion + item count
            HStack(spacing: 8) {
                if let occasion = outfit.occasion {
                    Text(occasion)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }

                Text("\(outfit.items.count) item\(outfit.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Thumbnail strip (up to 4 items in layer order)
            HStack(spacing: 6) {
                ForEach(Array(OutfitLayerOrder.sorted(outfit.items).prefix(4))) { item in
                    if let path = item.sourceImagePath,
                       let image = ImageStorageService.loadImage(relativePath: path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Circle()
                                    .fill(ColorMapping.color(for: item.primaryColor))
                                    .frame(width: 20, height: 20)
                            }
                    }
                }

                if outfit.items.count > 4 {
                    Text("+\(outfit.items.count - 4)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
