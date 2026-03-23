import SwiftUI
import SwiftData

struct ItemPickerSheet: View {
    @Bindable var viewModel: OutfitViewModel
    let wardrobeItems: [ClothingItem]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredItems: [ClothingItem] {
        if searchText.isEmpty { return wardrobeItems }
        let query = searchText.lowercased()
        return wardrobeItems.filter {
            $0.type.lowercased().contains(query) ||
            $0.category.lowercased().contains(query) ||
            $0.primaryColor.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Name field
                TextField("Outfit name (optional)", text: $viewModel.manualOutfitName)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tshirt",
                        description: Text("No items match your search.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(filteredItems) { item in
                                Button {
                                    viewModel.toggleItemSelection(item)
                                } label: {
                                    PickerGridCell(
                                        item: item,
                                        isSelected: viewModel.isItemSelected(item)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 80)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Bottom bar
                HStack {
                    Text("\(viewModel.manualSelectedItems.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)

                    Spacer()

                    Button("Create Outfit") {
                        viewModel.saveManualOutfit(from: wardrobeItems)
                    }
                    .buttonStyle(.themePrimary)
                    .disabled(viewModel.manualSelectedItems.isEmpty)
                    .frame(width: 180)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Pick Items")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.resetManualCreation()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Picker Grid Cell

struct PickerGridCell: View {
    let item: ClothingItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let path = item.sourceImagePath,
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

                // Selection badge
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.champagne : Theme.secondaryText)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 22, height: 22)
                    )
                    .padding(6)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.champagne, lineWidth: 2)
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
