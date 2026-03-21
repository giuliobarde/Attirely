import SwiftUI
import SwiftData

struct WardrobeView: View {
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var allItems: [ClothingItem]
    @State private var viewModel = WardrobeViewModel()
    @State private var isShowingAddItem = false
    @Environment(\.modelContext) private var modelContext

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WardrobeCategory.allCases, id: \.self) { category in
                            Button(category.rawValue) {
                                viewModel.selectedCategory = category
                            }
                            .buttonStyle(.bordered)
                            .tint(viewModel.selectedCategory == category ? .accentColor : .secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                let filtered = viewModel.filteredItems(from: allItems)

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tshirt",
                        description: Text(allItems.isEmpty
                            ? "Scan or add clothes to build your wardrobe."
                            : "No items match the current filter.")
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
            .navigationTitle("Wardrobe")
            .searchable(text: $viewModel.searchText)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            isShowingAddItem = true
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
            .sheet(isPresented: $isShowingAddItem) {
                AddItemView()
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let item = allItems.first(where: { $0.persistentModelID == id }) {
                    ItemDetailView(item: item)
                }
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
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(ColorMapping.color(for: item.primaryColor))
                                .frame(width: 32, height: 32)
                            Image(systemName: "tshirt")
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            Text(item.type)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(item.category)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
