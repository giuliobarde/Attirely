import SwiftUI
import SwiftData

private enum OutfitDetailAuxiliarySheet: String, Identifiable {
    case tagPicker
    case addItems

    var id: String { rawValue }
}

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var auxiliarySheet: OutfitDetailAuxiliarySheet?

    // Edit mode
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editOccasion = ""
    @State private var editItems: [ClothingItem] = []
    @State private var editTags: [Tag] = []

    private var tagsForChipRow: [Tag] {
        let base = isEditing ? editTags : Array(outfit.tags)
        return base.sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    if isEditing {
                        editHeader
                    } else {
                        viewHeader
                    }
                }
                .padding(.horizontal)

                // Tags (add/remove only in edit mode)
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tagsForChipRow) { tag in
                                if isEditing {
                                    TagChipView(tag: tag) {
                                        editTags.removeAll { $0.persistentModelID == tag.persistentModelID }
                                    }
                                } else {
                                    TagChipView(tag: tag)
                                }
                            }
                        }
                    }

                    if isEditing {
                        Button {
                            auxiliarySheet = .tagPicker
                        } label: {
                            Image(systemName: "tag")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 36)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)

                // Validation warnings
                if isEditing {
                    let warnings = OutfitLayerOrder.warnings(for: editItems)
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(warnings, id: \.self) { warning in
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Items in layer order
                VStack(spacing: 10) {
                    let displayItems = isEditing ? editItems : outfit.items
                    ForEach(OutfitLayerOrder.sorted(displayItems)) { item in
                        if isEditing {
                            OutfitItemCard(item: item, onRemove: {
                                editItems.removeAll { $0.persistentModelID == item.persistentModelID }
                            })
                        } else {
                            OutfitItemCard(item: item)
                        }
                    }

                    if isEditing {
                        Button {
                            auxiliarySheet = .addItems
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.champagne)
                                Text("Add Items")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.champagne)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.champagne.opacity(0.3), lineWidth: 1)
                            )
                        }
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
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancelEditing() }
                        .foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { saveEdits() }
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.champagne)
                        .disabled(editItems.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            enterEditMode()
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.secondaryText)
                        }

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
        }
        .confirmationDialog("Delete this outfit?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(outfit)
                try? modelContext.save()
                dismiss()
            }
        }
        .sheet(item: $auxiliarySheet) { sheet in
            switch sheet {
            case .tagPicker:
                TagPickerSheet(selectedTags: $editTags)
            case .addItems:
                OutfitEditItemPicker(currentItems: editItems) { newItems in
                    editItems.append(contentsOf: newItems)
                }
            }
        }
    }

    // MARK: - View Mode Header

    private var viewHeader: some View {
        Group {
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
    }

    // MARK: - Edit Mode Header

    private var editHeader: some View {
        Group {
            HStack {
                if outfit.isAIGenerated {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.champagne)
                }
                TextField("Outfit name", text: $editName)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.primaryText)
            }

            HStack(spacing: 8) {
                TextField("Occasion (optional)", text: $editOccasion)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.cardFill)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.cardBorder, lineWidth: 0.5))

                Text("\(editItems.count) item\(editItems.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()
            }
        }
    }

    // MARK: - Edit Mode Actions

    private func enterEditMode() {
        editName = outfit.name ?? ""
        editOccasion = outfit.occasion ?? ""
        editItems = outfit.items
        editTags = Array(outfit.tags)
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
    }

    private func saveEdits() {
        outfit.name = editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editName.trimmingCharacters(in: .whitespacesAndNewlines)
        outfit.occasion = editOccasion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        outfit.items = editItems
        outfit.tags = editTags
        try? modelContext.save()
        isEditing = false
    }
}

// MARK: - Outfit Item Card

private struct OutfitItemCard: View {
    let item: ClothingItem
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Remove button in edit mode
            if let onRemove {
                Button {
                    withAnimation { onRemove() }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }

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
