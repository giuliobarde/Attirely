import SwiftUI
import SwiftData

struct OutfitsView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var allOutfits: [Outfit]
    @Query private var wardrobeItems: [ClothingItem]
    @Query private var profiles: [UserProfile]
    @Query private var styleSummaries: [StyleSummary]
    @State private var viewModel = OutfitViewModel()
    @Environment(\.modelContext) private var modelContext
    @Bindable var weatherViewModel: WeatherViewModel
    var styleViewModel: StyleViewModel

    var body: some View {
        NavigationStack {
            Group {
                let filtered = viewModel.filteredOutfits(from: allOutfits)

                if filtered.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { outfit in
                                NavigationLink(value: outfit.persistentModelID) {
                                    OutfitRowCard(outfit: outfit) {
                                        viewModel.toggleFavorite(outfit)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .background(Theme.screenBackground)
            .navigationTitle("Outfits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation {
                            viewModel.showFavoritesOnly.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.showFavoritesOnly ? "star.fill" : "star")
                            .foregroundStyle(viewModel.showFavoritesOnly ? Theme.champagne : Theme.secondaryText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    WeatherWidgetView(viewModel: weatherViewModel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.isShowingItemPicker = true
                        } label: {
                            Label("Create Manually", systemImage: "hand.tap")
                        }
                        .disabled(wardrobeItems.isEmpty)

                        Button {
                            viewModel.isShowingGenerateSheet = true
                        } label: {
                            Label("AI Generate", systemImage: "sparkles")
                        }
                        .disabled(wardrobeItems.count < 2)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let outfit = allOutfits.first(where: { $0.persistentModelID == id }) {
                    OutfitDetailView(outfit: outfit)
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingGenerateSheet) {
            OutfitGenerationContextSheet(
                viewModel: viewModel,
                wardrobeItems: wardrobeItems,
                weatherViewModel: weatherViewModel,
                userProfile: profiles.first
            )
        }
        .sheet(isPresented: $viewModel.isShowingItemPicker) {
            ItemPickerSheet(
                viewModel: viewModel,
                wardrobeItems: wardrobeItems
            )
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.weatherViewModel = weatherViewModel
            viewModel.userProfile = profiles.first
            viewModel.styleViewModel = styleViewModel
            styleViewModel.modelContext = modelContext

            viewModel.updateStyleContext(from: styleSummaries.first)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if wardrobeItems.isEmpty {
            ContentUnavailableView(
                "Wardrobe is Empty",
                systemImage: "tshirt",
                description: Text("Scan some clothes first, then come back to build outfits.")
            )
        } else if viewModel.showFavoritesOnly {
            ContentUnavailableView(
                "No Favorites",
                systemImage: "star",
                description: Text("Star an outfit to add it to your favorites.")
            )
        } else {
            ContentUnavailableView(
                "No Outfits Yet",
                systemImage: "sparkles",
                description: Text("Tap + to create an outfit manually or let AI suggest one.")
            )
        }
    }
}
