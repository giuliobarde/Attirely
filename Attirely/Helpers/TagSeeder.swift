import Foundation
import SwiftData

struct TagSeeder {
    static let predefinedOutfitTags: [String] = [
        // Seasonal
        "spring", "summer", "fall", "winter",
        // Occasion
        "work", "casual", "date-night", "formal", "gym", "travel", "outdoor",
        // Special
        "siri"
    ]

    static let predefinedItemTags: [String] = [
        // Seasonal (overlap with outfit tags)
        "spring", "summer", "fall", "winter",
        // Item-specific
        "everyday", "statement", "layering", "seasonal-rotate"
    ]

    static func seed(in context: ModelContext) {
        seedTags(predefinedOutfitTags, scope: .outfit, in: context)
        seedTags(predefinedItemTags, scope: .item, in: context)
        try? context.save()
    }

    private static func seedTags(_ names: [String], scope: TagScope, in context: ModelContext) {
        let scopeStr = scope.rawValue
        for name in names {
            let normalized = Tag.normalized(name)
            let predicate = #Predicate<Tag> { $0.name == normalized && $0.scopeRaw == scopeStr }
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = (try? context.fetchCount(descriptor)) ?? 0
            guard existing == 0 else { continue }

            let tag = Tag(name: normalized, isPredefined: true, scope: scope)
            context.insert(tag)
        }
    }
}
