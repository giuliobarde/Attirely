import SwiftUI

struct ScanItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var type: String
    @State private var category: String
    @State private var primaryColor: String
    @State private var secondaryColor: String
    @State private var pattern: String
    @State private var fabric: String
    @State private var weight: String
    @State private var formality: String
    @State private var selectedSeasons: Set<String>
    @State private var fit: String?
    @State private var statementLevel: String
    @State private var itemDescription: String

    private let originalDTO: ClothingItemDTO
    private let onSave: (ClothingItemDTO) -> Void

    private let categories = ["Top", "Bottom", "Outerwear", "Footwear", "Accessory", "Full Body"]
    private let patterns = ["Solid", "Striped", "Plaid", "Floral", "Graphic", "Abstract", "Polka Dot", "Geometric", "Camo", "Other"]
    private let fabrics = ["Cotton", "Denim", "Wool", "Cashmere", "Acrylic", "Polyester", "Linen", "Leather", "Suede", "Silk", "Fleece", "Synthetic Blend"]
    private let weights = ["Lightweight", "Midweight", "Heavyweight"]
    private let formalities = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]
    private let fits = ["Slim", "Regular", "Relaxed", "Oversized", "Cropped"]
    private let statementLevels = ["Low", "Medium", "High"]
    private let allSeasons = ["Spring", "Summer", "Fall", "Winter"]

    init(dto: ClothingItemDTO, onSave: @escaping (ClothingItemDTO) -> Void) {
        self.originalDTO = dto
        self.onSave = onSave
        _type = State(initialValue: dto.type)
        _category = State(initialValue: dto.category)
        _primaryColor = State(initialValue: dto.primaryColor)
        _secondaryColor = State(initialValue: dto.secondaryColor ?? "")
        _pattern = State(initialValue: dto.pattern)
        _fabric = State(initialValue: dto.fabricEstimate)
        _weight = State(initialValue: dto.weight)
        _formality = State(initialValue: dto.formality)
        _selectedSeasons = State(initialValue: Set(dto.season))
        _fit = State(initialValue: dto.fit)
        _statementLevel = State(initialValue: dto.statementLevel)
        _itemDescription = State(initialValue: dto.description)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Type (e.g. Crew Neck T-Shirt)", text: $type)

                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }

                    TextField("Primary Color", text: $primaryColor)
                    TextField("Secondary Color (optional)", text: $secondaryColor)
                }

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

                if !originalDTO.tags.isEmpty {
                    Section("AI-Suggested Tags") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(originalDTO.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.champagne.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                Section("Description") {
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { applyEdits() }
                }
            }
        }
    }

    private func applyEdits() {
        var edited = originalDTO
        edited.type = type.trimmingCharacters(in: .whitespaces)
        edited.category = category
        edited.primaryColor = primaryColor.trimmingCharacters(in: .whitespaces)
        edited.secondaryColor = secondaryColor.isEmpty ? nil : secondaryColor.trimmingCharacters(in: .whitespaces)
        edited.pattern = pattern
        edited.fabricEstimate = fabric
        edited.weight = weight
        edited.formality = formality
        edited.season = Array(selectedSeasons)
        edited.fit = fit
        edited.statementLevel = statementLevel
        edited.description = itemDescription.trimmingCharacters(in: .whitespaces)
        onSave(edited)
        dismiss()
    }
}
