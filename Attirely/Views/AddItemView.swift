import SwiftUI
import PhotosUI
import SwiftData

struct AddItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Required
    @State private var type = ""
    @State private var category = "Top"
    @State private var primaryColor = ""

    // Defaulted
    @State private var secondaryColor = ""
    @State private var pattern = "Solid"
    @State private var fabric = "Cotton"
    @State private var weight = "Midweight"
    @State private var formality = "Casual"
    @State private var selectedSeasons: Set<String> = ["Spring", "Summer", "Fall", "Winter"]
    @State private var fit: String?
    @State private var statementLevel = "Low"
    @State private var itemDescription = ""
    @State private var brand = ""
    @State private var notes = ""

    // Tags
    @State private var selectedTags: [Tag] = []
    @State private var isShowingTagPicker = false

    // Photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    private var canSave: Bool {
        !type.trimmingCharacters(in: .whitespaces).isEmpty &&
        !primaryColor.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private let categories = ["Top", "Bottom", "Outerwear", "Footwear", "Accessory", "Full Body"]
    private let patterns = ["Solid", "Striped", "Plaid", "Floral", "Graphic", "Abstract", "Polka Dot", "Geometric", "Camo", "Other"]
    private let fabrics = ["Cotton", "Denim", "Wool", "Polyester", "Linen", "Leather", "Suede", "Silk", "Knit", "Fleece"]
    private let weights = ["Lightweight", "Midweight", "Heavyweight"]
    private let formalities = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]
    private let fits = ["Slim", "Regular", "Relaxed", "Oversized", "Cropped"]
    private let statementLevels = ["Low", "Medium", "High"]
    private let allSeasons = ["Spring", "Summer", "Fall", "Winter"]

    var body: some View {
        NavigationStack {
            Form {
                // Photo
                Section {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(selectedImage == nil ? "Add Photo" : "Change Photo", systemImage: "photo")
                    }
                }

                // Required
                Section("Item Details") {
                    TextField("Type (e.g. Crew Neck T-Shirt)", text: $type)

                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }

                    TextField("Primary Color (e.g. Navy Blue)", text: $primaryColor)
                    TextField("Secondary Color (optional)", text: $secondaryColor)
                }

                // Material
                Section("Material") {
                    Picker("Pattern", selection: $pattern) {
                        ForEach(patterns, id: \.self) { Text($0) }
                    }

                    Picker("Fabric", selection: $fabric) {
                        ForEach(fabrics, id: \.self) { Text($0) }
                    }

                    Picker("Weight", selection: $weight) {
                        ForEach(weights, id: \.self) { Text($0) }
                    }
                }

                // Style
                Section("Style") {
                    Picker("Formality", selection: $formality) {
                        ForEach(formalities, id: \.self) { Text($0) }
                    }

                    Picker("Fit", selection: $fit) {
                        Text("None").tag(String?.none)
                        ForEach(fits, id: \.self) { fit in
                            Text(fit).tag(Optional(fit))
                        }
                    }

                    Picker("Statement Level", selection: $statementLevel) {
                        ForEach(statementLevels, id: \.self) { Text($0) }
                    }
                }

                // Season
                Section("Season") {
                    ForEach(allSeasons, id: \.self) { season in
                        Toggle(season, isOn: Binding(
                            get: { selectedSeasons.contains(season) },
                            set: { isOn in
                                if isOn {
                                    selectedSeasons.insert(season)
                                } else {
                                    selectedSeasons.remove(season)
                                }
                            }
                        ))
                    }
                }

                // Tags
                Section("Tags") {
                    if selectedTags.isEmpty {
                        Text("No tags")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(selectedTags) { tag in
                                    TagChipView(tag: tag)
                                }
                            }
                        }
                    }

                    Button {
                        isShowingTagPicker = true
                    } label: {
                        Label("Edit Tags", systemImage: "tag")
                            .foregroundStyle(Theme.champagne)
                    }
                }

                // Description & notes
                Section("Description") {
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Your Notes") {
                    TextField("Brand", text: $brand)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveItem() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingTagPicker) {
                TagPickerSheet(selectedTags: $selectedTags, scope: .item)
            }
            .onChange(of: selectedPhoto) {
                Task {
                    if let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
        }
    }

    private func saveItem() {
        let item = ClothingItem(
            type: type.trimmingCharacters(in: .whitespaces),
            category: category,
            primaryColor: primaryColor.trimmingCharacters(in: .whitespaces),
            pattern: pattern,
            fabricEstimate: fabric,
            weight: weight,
            formality: formality,
            season: Array(selectedSeasons),
            statementLevel: statementLevel,
            itemDescription: itemDescription.trimmingCharacters(in: .whitespaces)
        )

        item.secondaryColor = secondaryColor.isEmpty ? nil : secondaryColor.trimmingCharacters(in: .whitespaces)
        item.fit = fit
        item.brand = brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
        item.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)

        // Save photo if provided
        if let selectedImage {
            if let path = try? ImageStorageService.saveClothingImage(selectedImage, id: item.id) {
                item.imagePath = path
            }
        }

        item.tags = selectedTags
        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
    }
}
