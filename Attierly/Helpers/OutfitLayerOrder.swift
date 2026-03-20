import Foundation

enum OutfitLayerOrder {
    private static let categoryRank: [String: Int] = [
        "Outerwear": 0,
        "Full Body": 1,
        "Top": 2,
        "Bottom": 3,
        "Footwear": 4,
        "Accessory": 5
    ]

    static func sorted(_ items: [ClothingItem]) -> [ClothingItem] {
        items.sorted {
            let a = categoryRank[$0.category] ?? 99
            let b = categoryRank[$1.category] ?? 99
            return a < b
        }
    }
}
