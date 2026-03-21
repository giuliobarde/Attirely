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

        return result
    }

    func deleteItem(_ item: ClothingItem, context: ModelContext) {
        if let path = item.imagePath {
            ImageStorageService.deleteImage(relativePath: path)
        }
        if let path = item.sourceImagePath {
            ImageStorageService.deleteImage(relativePath: path)
        }
        context.delete(item)
        try? context.save()
    }
}
