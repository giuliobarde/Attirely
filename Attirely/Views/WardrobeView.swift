import SwiftUI
import SwiftData
import PhotosUI

struct WardrobeView: View {
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var allItems: [ClothingItem]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var viewModel = WardrobeViewModel()
    @State private var scanViewModel = ScanViewModel()
    @State private var isShowingManualAdd = false
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @Environment(\.modelContext) private var modelContext
    @Bindable var weatherViewModel: WeatherViewModel
    var styleViewModel: StyleViewModel

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !allItems.isEmpty {
                    // Category filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(WardrobeCategory.allCases, id: \.self) { category in
                                Button {
                                    viewModel.selectedCategory = category
                                } label: {
                                    Text(category.rawValue)
                                        .themePill(isActive: viewModel.selectedCategory == category)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)

                }

                if allItems.isEmpty {
                    // Empty state onboarding
                    VStack(spacing: 24) {
                        Spacer()

                        VStack(spacing: 8) {
                            Image(systemName: "tshirt")
                                .font(.system(size: 56))
                                .foregroundStyle(Theme.champagne)
                            Text("Build Your Wardrobe")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                            Text("Scan clothes with your camera or add them manually")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 12) {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    scanViewModel.showingCamera = true
                                } label: {
                                    Label("Scan Clothes", systemImage: "camera")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.themePrimary)
                            }

                            Button {
                                isShowingPhotoPicker = true
                            } label: {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.themeSecondary)

                            Button {
                                isShowingManualAdd = true
                            } label: {
                                Label("Add Manually", systemImage: "square.and.pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.themeSecondary)
                        }
                        .padding(.horizontal, 32)

                        Spacer()
                    }
                } else {
                    let filtered = viewModel.filteredItems(from: allItems)

                    if filtered.isEmpty {
                        if !viewModel.selectedTagIDs.isEmpty {
                            ContentUnavailableView(
                                "No Matching Items",
                                systemImage: "tag",
                                description: Text("No items have all the selected tags.")
                            )
                        } else {
                            ContentUnavailableView(
                                "No Items",
                                systemImage: "tshirt",
                                description: Text("No items match the current filter.")
                            )
                        }
                    } else {
                        ScrollView {
                            switch viewModel.displayMode {
                            case .grid:
                                LazyVGrid(columns: gridColumns, spacing: 12) {
                                    ForEach(filtered) { item in
                                        if viewModel.isSelecting {
                                            Button {
                                                viewModel.toggleItemSelection(item)
                                            } label: {
                                                WardrobeGridCell(item: item)
                                                    .overlay(alignment: .bottomTrailing) {
                                                        selectionIndicator(for: item)
                                                    }
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            NavigationLink(value: item.persistentModelID) {
                                                WardrobeGridCell(item: item)
                                            }
                                            .buttonStyle(.plain)
                                            .onLongPressGesture {
                                                withAnimation {
                                                    viewModel.enterSelectionMode(with: item)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)

                            case .list:
                                LazyVStack(spacing: 12) {
                                    ForEach(filtered) { item in
                                        if viewModel.isSelecting {
                                            Button {
                                                viewModel.toggleItemSelection(item)
                                            } label: {
                                                ClothingItemCard(item: item)
                                                    .overlay(alignment: .bottomTrailing) {
                                                        selectionIndicator(for: item)
                                                    }
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            NavigationLink(value: item.persistentModelID) {
                                                ClothingItemCard(item: item)
                                            }
                                            .buttonStyle(.plain)
                                            .onLongPressGesture {
                                                withAnimation {
                                                    viewModel.enterSelectionMode(with: item)
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
            }
            .background(Theme.screenBackground)
            .navigationTitle("Wardrobe")
            .searchable(text: $viewModel.searchText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !allItems.isEmpty {
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
                    HStack(spacing: 16) {
                        WeatherWidgetView(viewModel: weatherViewModel)

                        Button {
                            viewModel.isShowingFilterSheet = true
                        } label: {
                            Image(systemName: viewModel.activeFilterCount > 0
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                                .foregroundStyle(viewModel.activeFilterCount > 0 ? Theme.champagne : Theme.secondaryText)
                                .overlay(alignment: .topTrailing) {
                                    if viewModel.activeFilterCount > 0 {
                                        Text("\(viewModel.activeFilterCount)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 16, height: 16)
                                            .background(Theme.champagne)
                                            .clipShape(Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                        }

                        Menu {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    scanViewModel.showingCamera = true
                                } label: {
                                    Label("Scan with Camera", systemImage: "camera")
                                }
                            }

                            Button {
                                isShowingPhotoPicker = true
                            } label: {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                            }

                            Button {
                                isShowingManualAdd = true
                            } label: {
                                Label("Add Manually", systemImage: "square.and.pencil")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }

                        Button {
                            withAnimation {
                                viewModel.displayMode = viewModel.displayMode == .grid ? .list : .grid
                            }
                        } label: {
                            Image(systemName: viewModel.displayMode == .grid ? "list.bullet" : "square.grid.2x2")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isSelecting && !viewModel.selectedItemIDs.isEmpty {
                    bulkActionBar
                }
            }
            .sheet(isPresented: $viewModel.isShowingFilterSheet) {
                WardrobeFilterSheet(
                    selectedTagIDs: $viewModel.selectedTagIDs,
                    selectedFormalities: $viewModel.selectedFormalities,
                    selectedColors: $viewModel.selectedColors,
                    availableFormalities: viewModel.availableFormalities(from: allItems),
                    availableColors: viewModel.availableColors(from: allItems),
                    items: allItems
                ) {
                    viewModel.clearAllFilters()
                }
            }
            .sheet(isPresented: $isShowingManualAdd) {
                AddItemView()
            }
            .sheet(isPresented: $viewModel.isShowingBulkTagEdit) {
                BulkTagEditSheet(
                    scope: .item,
                    selectedItemIDs: viewModel.selectedItemIDs,
                    allItems: allItems
                ) { edits in
                    viewModel.applyBulkTagEdits(edits: edits, items: allItems, allTags: allTags)
                    try? modelContext.save()
                }
            }
            .alert("Delete Items?", isPresented: $viewModel.isShowingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteSelectedItems(items: allItems, context: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Delete \(viewModel.selectedItemIDs.count) item\(viewModel.selectedItemIDs.count == 1 ? "" : "s")? This cannot be undone.")
            }
            .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .fullScreenCover(isPresented: $scanViewModel.showingCamera) {
                ImagePicker(sourceType: .camera) { image in
                    scanViewModel.analyzeImage(image)
                }
                .ignoresSafeArea()
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let item = allItems.first(where: { $0.persistentModelID == id }) {
                    ItemDetailView(item: item)
                }
            }
            .navigationDestination(isPresented: $scanViewModel.showingResults) {
                ResultsView(viewModel: scanViewModel)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        scanViewModel.analyzeImage(image)
                    }
                }
                selectedPhotoItem = nil
            }
            .onAppear {
                scanViewModel.modelContext = modelContext
                scanViewModel.styleViewModel = styleViewModel
                styleViewModel.modelContext = modelContext
            }
        }
    }

    // MARK: - Selection Indicator

    private func selectionIndicator(for item: ClothingItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.persistentModelID)
        return Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Theme.champagne : Theme.secondaryText)
            .padding(6)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .padding(8)
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedItemIDs.count) selected")
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

struct WardrobeGridCell: View {
    let item: ClothingItem

    var body: some View {
        VStack(spacing: 6) {
            if let path = item.imagePath ?? item.sourceImagePath,
               let image = ImageStorageService.loadImage(relativePath: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.placeholderFill)
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(ColorMapping.color(for: item.primaryColor))
                                .frame(width: 32, height: 32)
                            Image(systemName: "tshirt")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
            }

            Text(item.type)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Text(item.category)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
