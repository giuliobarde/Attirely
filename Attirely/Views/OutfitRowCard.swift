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
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                Spacer()

                if outfit.isAIGenerated {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.champagne)
                }

                Button {
                    onFavoriteToggle()
                } label: {
                    Image(systemName: outfit.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(outfit.isFavorite ? Theme.champagne : Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            // Occasion + item count
            HStack(spacing: 8) {
                if let occasion = outfit.occasion {
                    Text(occasion)
                        .themePill()
                }

                Text("\(outfit.items.count) item\(outfit.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
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
                            .fill(Theme.placeholderFill)
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
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 48, height: 48)
                        .background(Theme.placeholderFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .themeCard()
    }
}
