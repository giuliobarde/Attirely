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

    static func warnings(for items: [ClothingItem]) -> [String] {
        var results: [String] = []
        var counts: [String: Int] = [:]
        for item in items {
            counts[item.category, default: 0] += 1
        }

        if (counts["Footwear"] ?? 0) > 1 {
            results.append("This outfit has multiple pairs of footwear")
        }
        if (counts["Bottom"] ?? 0) > 1 {
            results.append("This outfit has multiple bottoms")
        }
        if (counts["Full Body"] ?? 0) > 1 {
            results.append("This outfit has multiple full-body items")
        }
        if (counts["Full Body"] ?? 0) > 0 && ((counts["Top"] ?? 0) > 0 || (counts["Bottom"] ?? 0) > 0) {
            results.append("Full-body item usually replaces separate top/bottom")
        }

        return results
    }
}
