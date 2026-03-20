import SwiftUI
import SwiftData

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if outfit.isAIGenerated {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                        Text(outfit.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

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

                        Spacer()

                        Text(outfit.createdAt.formatted(.dateTime.month().day().year()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                        Text(reasoning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
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
                            .foregroundStyle(outfit.isFavorite ? .yellow : .secondary)
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
                    .fill(Color.secondary.opacity(0.15))
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

                HStack(spacing: 6) {
                    Circle()
                        .fill(ColorMapping.color(for: item.primaryColor))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    Text(item.primaryColor)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.formality)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Category label
            Text(item.category)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
