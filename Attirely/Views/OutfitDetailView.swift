import SwiftUI
import SwiftData

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isShowingTagPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if outfit.isAIGenerated {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(Theme.champagne)
                        }
                        Text(outfit.displayName)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.primaryText)
                    }

                    HStack(spacing: 8) {
                        if let occasion = outfit.occasion {
                            Text(occasion)
                                .themePill()
                        }

                        Text("\(outfit.items.count) item\(outfit.items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)

                        Spacer()

                        Text(outfit.createdAt.formatted(.dateTime.month().day().year()))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal)

                // Tags
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(outfit.tags.sorted(by: { $0.name < $1.name })) { tag in
                                TagChipView(tag: tag) {
                                    outfit.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
                                    try? modelContext.save()
                                }
                            }
                        }
                    }

                    Button {
                        isShowingTagPicker = true
                    } label: {
                        Image(systemName: "tag")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal)

                // Items in layer order
                VStack(spacing: 10) {
                    ForEach(OutfitLayerOrder.sorted(outfit.items)) { item in
                        OutfitItemCard(item: item)
                    }
                }
                .padding(.horizontal)

                // AI reasoning
                if let reasoning = outfit.reasoning, outfit.isAIGenerated {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why this works")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.secondaryText)
                        Text(reasoning)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.cardBorder, lineWidth: 0.5)
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Outfit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        outfit.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: outfit.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(outfit.isFavorite ? Theme.champagne : Theme.secondaryText)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .confirmationDialog("Delete this outfit?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(outfit)
                try? modelContext.save()
                dismiss()
            }
        }
        .sheet(isPresented: $isShowingTagPicker) {
            TagPickerSheet(outfit: outfit)
        }
    }
}

// MARK: - Outfit Item Card

private struct OutfitItemCard: View {
    let item: ClothingItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let path = item.sourceImagePath,
               let image = ImageStorageService.loadImage(relativePath: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.placeholderFill)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Circle()
                            .fill(ColorMapping.color(for: item.primaryColor))
                            .frame(width: 24, height: 24)
                    }
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.type)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(ColorMapping.color(for: item.primaryColor))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
                    Text(item.primaryColor)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(item.formality)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            // Category label
            Text(item.category)
                .themeTag()
        }
        .themeCard()
    }
}
