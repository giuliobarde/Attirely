import SwiftUI
import SwiftData

struct OutfitEditItemPicker: View {
    let currentItems: [ClothingItem]
    let onAdd: ([ClothingItem]) -> Void

    @Query private var allItems: [ClothingItem]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var searchText = ""

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var availableItems: [ClothingItem] {
        let currentIDs = Set(currentItems.map(\.persistentModelID))
        let pool = allItems.filter { !currentIDs.contains($0.persistentModelID) }
        if searchText.isEmpty { return pool }
        let query = searchText.lowercased()
        return pool.filter {
            $0.type.lowercased().contains(query) ||
            $0.category.lowercased().contains(query) ||
            $0.primaryColor.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableItems.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tshirt",
                        description: Text(searchText.isEmpty
                            ? "All wardrobe items are already in this outfit."
                            : "No items match your search.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(availableItems) { item in
                                Button {
                                    toggleSelection(item)
                                } label: {
                                    PickerGridCell(
                                        item: item,
                                        isSelected: selectedIDs.contains(item.persistentModelID)
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
                HStack {
                    Text("\(selectedIDs.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)

                    Spacer()

                    Button("Add to Outfit") {
                        let items = allItems.filter { selectedIDs.contains($0.persistentModelID) }
                        onAdd(items)
                        dismiss()
                    }
                    .buttonStyle(.themePrimary)
                    .disabled(selectedIDs.isEmpty)
                    .frame(width: 180)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Add Items")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggleSelection(_ item: ClothingItem) {
        if selectedIDs.contains(item.persistentModelID) {
            selectedIDs.remove(item.persistentModelID)
        } else {
            selectedIDs.insert(item.persistentModelID)
        }
    }
}
