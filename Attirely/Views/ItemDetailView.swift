import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: ClothingItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    private let allSeasons = ["Spring", "Summer", "Fall", "Winter"]

    var body: some View {
        Form {
            // Image section
            Section {
                if let path = item.imagePath ?? item.sourceImagePath,
                   let image = ImageStorageService.loadImage(relativePath: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }
            }

            // Core details
            Section("Item Details") {
                editableField("Type", value: $item.type, field: "type")
                editableField("Category", value: $item.category, field: "category")
                editableField("Primary Color", value: $item.primaryColor, field: "primaryColor")
                optionalField("Secondary Color", value: $item.secondaryColor, field: "secondaryColor")
                editableField("Pattern", value: $item.pattern, field: "pattern")
                editableField("Fabric", value: $item.fabricEstimate, field: "fabricEstimate")
            }

            // Style attributes
            Section("Style") {
                editableField("Weight", value: $item.weight, field: "weight")
                editableField("Formality", value: $item.formality, field: "formality")
                editableField("Statement Level", value: $item.statementLevel, field: "statementLevel")
                optionalField("Fit", value: $item.fit, field: "fit")
            }

            // Season
            Section("Season") {
                ForEach(allSeasons, id: \.self) { season in
                    Toggle(season, isOn: Binding(
                        get: { item.season.contains(season) },
                        set: { isOn in
                            if isOn {
                                if !item.season.contains(season) {
                                    item.season.append(season)
                                }
                            } else {
                                item.season.removeAll { $0 == season }
                            }
                        }
                    ))
                }
            }

            // Description
            Section("Description") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Description", text: $item.itemDescription, axis: .vertical)
                        .lineLimit(3...6)
                    if let original = item.originalAIValue(for: "itemDescription"),
                       original != item.itemDescription {
                        Text("AI detected: \(original)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            // User fields
            Section("Your Notes") {
                TextField("Brand", text: Binding(
                    get: { item.brand ?? "" },
                    set: { item.brand = $0.isEmpty ? nil : $0 }
                ))

                TextField("Notes", text: Binding(
                    get: { item.notes ?? "" },
                    set: { item.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }

            // Delete
            Section {
                Button("Delete Item", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.screenBackground)
        .navigationTitle(item.type)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    item.updatedAt = Date()
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
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
        }
    }

    private func editableField(_ label: String, value: Binding<String>, field: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(label, text: value)
            if let original = item.originalAIValue(for: field),
               original != value.wrappedValue {
                Text("AI detected: \(original)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func optionalField(_ label: String, value: Binding<String?>, field: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(label, text: Binding(
                get: { value.wrappedValue ?? "" },
                set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
            ))
            if let original = item.originalAIValue(for: field),
               original != (value.wrappedValue ?? "") {
                Text("AI detected: \(original)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
