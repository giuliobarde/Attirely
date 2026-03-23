import SwiftUI
import SwiftData
import PhotosUI

struct WardrobeView: View {
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var allItems: [ClothingItem]
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
                    // Category filter — only when wardrobe has items
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
                        ContentUnavailableView(
                            "No Items",
                            systemImage: "tshirt",
                            description: Text("No items match the current filter.")
                        )
                    } else {
                        ScrollView {
                            switch viewModel.displayMode {
                            case .grid:
                                LazyVGrid(columns: gridColumns, spacing: 12) {
                                    ForEach(filtered) { item in
                                        NavigationLink(value: item.persistentModelID) {
                                            WardrobeGridCell(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)

                            case .list:
                                LazyVStack(spacing: 12) {
                                    ForEach(filtered) { item in
                                        NavigationLink(value: item.persistentModelID) {
                                            ClothingItemCard(item: item)
                                        }
                                        .buttonStyle(.plain)
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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        WeatherWidgetView(viewModel: weatherViewModel)

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
            .sheet(isPresented: $isShowingManualAdd) {
                AddItemView()
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
