import SwiftUI

struct OutfitGenerationContextSheet: View {
    @Bindable var viewModel: OutfitViewModel
    let wardrobeItems: [ClothingItem]
    @Environment(\.dismiss) private var dismiss

    private let occasions = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]
    private let seasons = ["Spring", "Summer", "Fall", "Winter"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Context (Optional)") {
                    Picker("Occasion", selection: $viewModel.selectedOccasion) {
                        Text("Any").tag(String?.none)
                        ForEach(occasions, id: \.self) { occasion in
                            Text(occasion).tag(Optional(occasion))
                        }
                    }

                    Picker("Season", selection: $viewModel.selectedSeason) {
                        Text("Any").tag(String?.none)
                        ForEach(seasons, id: \.self) { season in
                            Text(season).tag(Optional(season))
                        }
                    }
                }

                Section {
                    if viewModel.isGenerating {
                        HStack {
                            Spacer()
                            ProgressView("Generating outfits...")
                            Spacer()
                        }
                    } else {
                        Button {
                            viewModel.generateOutfits(from: wardrobeItems)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Generate Outfits", systemImage: "sparkles")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("AI Outfit Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.resetGenerationContext()
                        dismiss()
                    }
                    .disabled(viewModel.isGenerating)
                }
            }
        }
    }
}
