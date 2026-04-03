import SwiftUI
import SwiftData

struct OutfitsView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var allOutfits: [Outfit]
    @Query private var wardrobeItems: [ClothingItem]
    @Query private var profiles: [UserProfile]
    @Query private var styleSummaries: [StyleSummary]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var viewModel = OutfitViewModel()
    @State private var isShowingStyleModeOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @Bindable var weatherViewModel: WeatherViewModel
    var styleViewModel: StyleViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TagFilterBar(
                    selectedTagIDs: $viewModel.selectedTagIDs,
                    scope: .outfit,
                    outfits: allOutfits
                )

                Group {
                    let filtered = viewModel.filteredOutfits(from: allOutfits)

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filtered) { outfit in
                                    if viewModel.isSelecting {
                                        Button {
                                            viewModel.toggleOutfitSelection(outfit)
                                        } label: {
                                            OutfitRowCard(outfit: outfit) {
                                                viewModel.toggleFavorite(outfit)
                                            }
                                            .overlay(alignment: .bottomTrailing) {
                                                selectionIndicator(for: outfit)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink(value: outfit.persistentModelID) {
                                            OutfitRowCard(outfit: outfit) {
                                                viewModel.toggleFavorite(outfit)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .onLongPressGesture {
                                            withAnimation {
                                                viewModel.enterSelectionMode(with: outfit)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .background(Theme.screenBackground)
            .navigationTitle("Outfits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation {
                                viewModel.showFavoritesOnly.toggle()
                            }
                        } label: {
                            Image(systemName: viewModel.showFavoritesOnly ? "star.fill" : "star")
                                .foregroundStyle(viewModel.showFavoritesOnly ? Theme.champagne : Theme.secondaryText)
                        }

                        Button {
                            withAnimation {
                                if viewModel.isSelecting {
                                    viewModel.exitSelectionMode()
                                } else {
                                    viewModel.isSelecting = true
                                }
                            }
                        } label: {
                            Text(viewModel.isSelecting ? "Done" : "Select")
                                .font(.subheadline)
                                .foregroundStyle(viewModel.isSelecting ? Theme.champagne : Theme.secondaryText)
                        }
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
            .safeAreaInset(edge: .bottom) {
                if viewModel.isSelecting && !viewModel.selectedOutfitIDs.isEmpty {
                    bulkTagBar
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
        .sheet(isPresented: $viewModel.isShowingBulkTagEdit) {
            BulkTagEditSheet(
                scope: .outfit,
                selectedOutfitIDs: viewModel.selectedOutfitIDs,
                allOutfits: allOutfits
            ) { edits in
                viewModel.applyBulkTagEdits(edits: edits, outfits: allOutfits, allTags: allTags)
            }
        }
        .alert("Delete Outfits?", isPresented: $viewModel.isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedOutfits(outfits: allOutfits)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(viewModel.selectedOutfitIDs.count) outfit\(viewModel.selectedOutfitIDs.count == 1 ? "" : "s")? This cannot be undone.")
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.weatherViewModel = weatherViewModel
            viewModel.userProfile = profiles.first
            viewModel.styleViewModel = styleViewModel
            styleViewModel.modelContext = modelContext

            viewModel.updateStyleContext(from: styleSummaries.first)

            if let profile = profiles.first,
               !profile.hasSeenStyleModeOnboarding,
               !wardrobeItems.isEmpty {
                isShowingStyleModeOnboarding = true
            }
        }
        .sheet(isPresented: $isShowingStyleModeOnboarding) {
            if let profile = profiles.first {
                StyleModeOnboardingSheet(isPresented: $isShowingStyleModeOnboarding) { chosen in
                    profile.styleMode = chosen
                    profile.hasSeenStyleModeOnboarding = true
                    profile.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Empty State

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
        } else if !viewModel.selectedTagIDs.isEmpty {
            ContentUnavailableView(
                "No Matching Outfits",
                systemImage: "tag",
                description: Text("No outfits have all the selected tags.")
            )
        } else {
            ContentUnavailableView(
                "No Outfits Yet",
                systemImage: "sparkles",
                description: Text("Tap + to create an outfit manually or let AI suggest one.")
            )
        }
    }

    // MARK: - Selection Mode

    private func selectionIndicator(for outfit: Outfit) -> some View {
        let isSelected = viewModel.selectedOutfitIDs.contains(outfit.persistentModelID)
        return Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Theme.champagne : Theme.secondaryText)
            .padding(6)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .padding(8)
    }

    // MARK: - Bulk Tag Bar

    private var bulkTagBar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedOutfitIDs.count) selected")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            Spacer()

            Button("Edit Tags") { viewModel.isShowingBulkTagEdit = true }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.champagne)

            Button {
                viewModel.isShowingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

}
