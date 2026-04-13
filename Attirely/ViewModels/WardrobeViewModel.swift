import SwiftUI
import SwiftData

enum WardrobeCategory: String, CaseIterable {
    case all = "All"
    case top = "Top"
    case bottom = "Bottom"
    case outerwear = "Outerwear"
    case footwear = "Footwear"
    case accessory = "Accessory"
    case fullBody = "Full Body"
}

enum WardrobeDisplayMode {
    case grid
    case list
}

@Observable
class WardrobeViewModel {
    var selectedCategory: WardrobeCategory = .all
    var displayMode: WardrobeDisplayMode = .grid
    var searchText: String = ""

    // Attribute filtering
    var selectedFormalities: Set<String> = []
    var selectedColors: Set<String> = []

    // Tag filtering
    var selectedTagIDs: Set<PersistentIdentifier> = []

    // Bulk selection
    var isSelecting = false
    var selectedItemIDs: Set<PersistentIdentifier> = []
    var isShowingBulkTagEdit = false
    var isShowingDeleteConfirmation = false
    var affectedOutfits: [Outfit] = []
    var isShowingFilterSheet = false

    var activeFilterCount: Int {
        selectedTagIDs.count + selectedFormalities.count + selectedColors.count
    }

    func clearAllFilters() {
        selectedTagIDs.removeAll()
        selectedFormalities.removeAll()
        selectedColors.removeAll()
    }

    func filteredItems(from items: [ClothingItem]) -> [ClothingItem] {
        var result = items

        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory.rawValue }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.type.localizedCaseInsensitiveContains(searchText) ||
                $0.primaryColor.localizedCaseInsensitiveContains(searchText) ||
                $0.itemDescription.localizedCaseInsensitiveContains(searchText) ||
                ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if !selectedTagIDs.isEmpty {
            result = result.filter { item in
                selectedTagIDs.allSatisfy { tagID in
                    item.tags.contains { $0.persistentModelID == tagID }
                }
            }
        }

        if !selectedFormalities.isEmpty {
            result = result.filter { selectedFormalities.contains($0.formality) }
        }

        if !selectedColors.isEmpty {
            result = result.filter { selectedColors.contains($0.primaryColor) }
        }

        return result
    }

    // MARK: - Available Filter Options

    private static let formalityDisplayOrder = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]

    func availableFormalities(from items: [ClothingItem]) -> [String] {
        let present = Set(items.map(\.formality))
        return Self.formalityDisplayOrder.filter { present.contains($0) }
    }

    func availableColors(from items: [ClothingItem]) -> [String] {
        Array(Set(items.map(\.primaryColor))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Bulk Selection

    func enterSelectionMode(with item: ClothingItem) {
        isSelecting = true
        selectedItemIDs = [item.persistentModelID]
    }

    func toggleItemSelection(_ item: ClothingItem) {
        if selectedItemIDs.contains(item.persistentModelID) {
            selectedItemIDs.remove(item.persistentModelID)
        } else {
            selectedItemIDs.insert(item.persistentModelID)
        }
    }

    func exitSelectionMode() {
        isSelecting = false
        selectedItemIDs = []
    }

    func applyBulkTagEdits(edits: [PersistentIdentifier: Bool], items: [ClothingItem], allTags: [Tag]) {
        let targets = items.filter { selectedItemIDs.contains($0.persistentModelID) }
        for (tagID, shouldHave) in edits {
            guard let tag = allTags.first(where: { $0.persistentModelID == tagID }) else { continue }
            for item in targets {
                let has = item.tags.contains { $0.persistentModelID == tagID }
                if shouldHave && !has {
                    item.tags.append(tag)
                } else if !shouldHave && has {
                    item.tags.removeAll { $0.persistentModelID == tagID }
                }
            }
        }
        exitSelectionMode()
    }

    func computeAffectedOutfits(items: [ClothingItem]) {
        let targets = items.filter { selectedItemIDs.contains($0.persistentModelID) }
        var seen = Set<PersistentIdentifier>()
        var outfits: [Outfit] = []
        for item in targets {
            for outfit in item.outfits {
                if seen.insert(outfit.persistentModelID).inserted {
                    outfits.append(outfit)
                }
            }
        }
        affectedOutfits = outfits
    }

    func deleteSelectedItems(items: [ClothingItem], context: ModelContext) {
        let targets = items.filter { selectedItemIDs.contains($0.persistentModelID) }

        // Delete affected outfits first (before nullify severs references)
        for outfit in affectedOutfits {
            context.delete(outfit)
        }

        for item in targets {
            for path in item.allImagePaths {
                ImageStorageService.deleteImage(relativePath: path)
            }
            context.delete(item)
        }
        try? context.save()
        affectedOutfits = []
        exitSelectionMode()
    }

    // MARK: - Single Item Delete

    func deleteItem(_ item: ClothingItem, affectedOutfits: [Outfit], context: ModelContext) {
        for outfit in affectedOutfits {
            context.delete(outfit)
        }
        for path in item.allImagePaths {
            ImageStorageService.deleteImage(relativePath: path)
        }
        context.delete(item)
        try? context.save()
    }
}
