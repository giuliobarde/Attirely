import SwiftUI

struct OutfitGenerationContextSheet: View {
    @Bindable var viewModel: OutfitViewModel
    let wardrobeItems: [ClothingItem]
    var weatherViewModel: WeatherViewModel?
    var userProfile: UserProfile?
    @Environment(\.dismiss) private var dismiss

    private let occasions = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]
    private let seasons = ["Spring", "Summer", "Fall", "Winter"]

    var body: some View {
        NavigationStack {
            Form {
                if let wvm = weatherViewModel, let snapshot = wvm.snapshot, !wvm.userOverridesWeather {
                    Section("Current Weather") {
                        HStack(spacing: 10) {
                            Image(systemName: snapshot.current.conditionSymbol)
                                .font(.title3)
                                .foregroundStyle(Theme.champagne)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(TemperatureFormatter.format(snapshot.current.temperature, unit: userProfile?.temperatureUnit ?? .celsius)) — \(snapshot.current.conditionDescription)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.primaryText)
                                if let city = snapshot.locationName {
                                    Text(city)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                Section {
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
                } header: {
                    Text("Context (Optional)")
                } footer: {
                    if weatherViewModel?.snapshot != nil, weatherViewModel?.userOverridesWeather != true {
                        Text("Season auto-populated from current weather. You can override it.")
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
                        .buttonStyle(.themePrimary)
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
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("AI Outfit Generator")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.autoPopulateSeason()
            }
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
