import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: ClothingItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var affectedOutfits: [Outfit] = []
    @State private var itemTags: [Tag] = []
    @State private var isShowingTagPicker = false
    @State private var isDetailsExpanded = true
    @State private var isMaterialExpanded = false
    @State private var isStyleExpanded = false
    @State private var isSeasonExpanded = false
    @State private var isTagsExpanded = false
    @State private var isNotesExpanded = false

    private let categories = ["Top", "Bottom", "Outerwear", "Footwear", "Accessory", "Full Body"]
    private let patterns = [
        "Solid", "Striped", "Plaid", "Checkered", "Floral", "Polka Dot",
        "Paisley", "Geometric", "Abstract", "Animal Print", "Camouflage",
        "Herringbone", "Houndstooth", "Color Block"
    ]
    private let fabrics = [
        "Cotton", "Polyester", "Wool", "Silk", "Linen", "Denim", "Leather",
        "Suede", "Nylon", "Cashmere", "Fleece", "Velvet", "Satin", "Tweed",
        "Corduroy", "Chiffon", "Jersey", "Synthetic Blend"
    ]
    private let weights = ["Lightweight", "Midweight", "Heavyweight"]
    private let formalities = [
        "Casual", "Smart Casual", "Business Casual", "Business",
        "Cocktail", "Formal", "Black Tie"
    ]
    private let statementLevels = ["Low", "Medium", "High"]
    private let fits = ["Slim", "Regular", "Relaxed", "Oversized", "Tailored"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                imageSection
                detailsSection
                materialSection
                styleSection
                seasonSection
                tagsSection
                notesSection
                deleteSection
            }
            .padding()
        }
        .background(Theme.screenBackground)
        .navigationTitle(item.type)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    item.tags = itemTags
                    item.updatedAt = Date()
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .onAppear { itemTags = item.tags }
        .sheet(isPresented: $isShowingTagPicker) {
            TagPickerSheet(selectedTags: $itemTags, scope: .item)
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                for outfit in affectedOutfits {
                    modelContext.delete(outfit)
                }
                if let path = item.imagePath {
                    ImageStorageService.deleteImage(relativePath: path)
                }
                if let path = item.sourceImagePath {
                    ImageStorageService.deleteImage(relativePath: path)
                }
                modelContext.delete(item)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                affectedOutfits = []
            }
        } message: {
            if affectedOutfits.isEmpty {
                Text("This cannot be undone.")
            } else {
                let names = affectedOutfits.prefix(5).map(\.displayName).joined(separator: ", ")
                let suffix = affectedOutfits.count > 5 ? " + \(affectedOutfits.count - 5) more" : ""
                Text("This will also delete \(affectedOutfits.count) outfit\(affectedOutfits.count == 1 ? "" : "s"): \(names)\(suffix). This cannot be undone.")
            }
        }
    }

    // MARK: - Image

    private var imageSection: some View {
        Group {
            if let path = item.imagePath ?? item.sourceImagePath,
               let image = ImageStorageService.loadImage(relativePath: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        CollapsibleSection(title: "Details", isExpanded: $isDetailsExpanded, titleWeight: .semibold) {
            VStack(alignment: .leading, spacing: 14) {
                editableField("Type", value: $item.type, field: "type")

                PillPickerField(
                    label: "Category",
                    options: categories,
                    selection: $item.category,
                    aiOriginalValue: item.originalAIValue(for: "category")
                )

                ColorSwatchPicker(
                    label: "Primary Color",
                    selection: $item.primaryColor,
                    aiOriginalValue: item.originalAIValue(for: "primaryColor")
                )

                ColorSwatchPicker(
                    label: "Secondary Color",
                    selection: Binding(
                        get: { item.secondaryColor ?? "" },
                        set: { item.secondaryColor = $0.isEmpty ? nil : $0 }
                    ),
                    allowsNone: true,
                    aiOriginalValue: item.originalAIValue(for: "secondaryColor")
                )
            }
        }
    }

    // MARK: - Material

    private var materialSection: some View {
        CollapsibleSection(title: "Material", isExpanded: $isMaterialExpanded, titleWeight: .semibold) {
            VStack(alignment: .leading, spacing: 14) {
                PillPickerField(
                    label: "Pattern",
                    options: patterns,
                    selection: $item.pattern,
                    allowsCustom: true,
                    aiOriginalValue: item.originalAIValue(for: "pattern")
                )

                PillPickerField(
                    label: "Fabric",
                    options: fabrics,
                    selection: $item.fabricEstimate,
                    allowsCustom: true,
                    aiOriginalValue: item.originalAIValue(for: "fabricEstimate")
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    Picker("Weight", selection: $item.weight) {
                        ForEach(weights, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let original = item.originalAIValue(for: "weight"), original != item.weight {
                        Text("AI detected: \(original)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Style

    private var styleSection: some View {
        CollapsibleSection(title: "Style", isExpanded: $isStyleExpanded, titleWeight: .semibold) {
            VStack(alignment: .leading, spacing: 14) {
                PillPickerField(
                    label: "Formality",
                    options: formalities,
                    selection: $item.formality,
                    aiOriginalValue: item.originalAIValue(for: "formality")
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Statement Level")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    Picker("Statement Level", selection: $item.statementLevel) {
                        ForEach(statementLevels, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let original = item.originalAIValue(for: "statementLevel"), original != item.statementLevel {
                        Text("AI detected: \(original)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                OptionalPillPickerField(
                    label: "Fit",
                    options: fits,
                    selection: $item.fit,
                    aiOriginalValue: item.originalAIValue(for: "fit")
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Formality Floor")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    Picker("Formality Floor", selection: Binding(
                        get: { item.formalityFloor ?? "None" },
                        set: { item.formalityFloor = $0 == "None" ? nil : $0 }
                    )) {
                        Text("None").tag("None")
                        Text("Business").tag("Business")
                        Text("Cocktail").tag("Cocktail")
                        Text("Formal").tag("Formal")
                        Text("Black Tie").tag("Black Tie")
                    }
                }
            }
        }
    }

    // MARK: - Season

    private var seasonSection: some View {
        CollapsibleSection(title: "Season", isExpanded: $isSeasonExpanded, titleWeight: .semibold) {
            HStack(spacing: 8) {
                ForEach(["Spring", "Summer", "Fall", "Winter"], id: \.self) { season in
                    let isActive = item.season.contains(season)
                    Button {
                        if isActive {
                            item.season.removeAll { $0 == season }
                        } else {
                            item.season.append(season)
                        }
                    } label: {
                        Text(season)
                            .themePill(isActive: isActive)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        CollapsibleSection(title: "Tags", isExpanded: $isTagsExpanded, titleWeight: .semibold) {
            VStack(alignment: .leading, spacing: 8) {
                if itemTags.isEmpty {
                    Text("No tags")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(itemTags) { tag in
                            TagChipView(tag: tag)
                        }
                    }
                }

                Button {
                    isShowingTagPicker = true
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                        .font(.subheadline)
                        .foregroundStyle(Theme.champagne)
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        CollapsibleSection(title: "Notes", isExpanded: $isNotesExpanded, titleWeight: .semibold) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    TextField("Description", text: $item.itemDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    if let original = item.originalAIValue(for: "itemDescription"),
                       original != item.itemDescription {
                        Text("AI detected: \(original)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Brand")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    TextField("Brand", text: Binding(
                        get: { item.brand ?? "" },
                        set: { item.brand = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)

                    TextField("Notes", text: Binding(
                        get: { item.notes ?? "" },
                        set: { item.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button("Delete Item", role: .destructive) {
            affectedOutfits = item.outfits
            showDeleteConfirmation = true
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func editableField(_ label: String, value: Binding<String>, field: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            TextField(label, text: value)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            if let original = item.originalAIValue(for: field),
               original != value.wrappedValue {
                Text("AI detected: \(original)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
