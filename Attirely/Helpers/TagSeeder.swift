import Foundation
import SwiftData

struct TagSeeder {
    static let predefined: [String] = [
        // Seasonal
        "spring", "summer", "fall", "winter",
        // Occasion
        "work", "casual", "date-night", "formal", "gym", "travel", "outdoor",
        // Special
        "siri"
    ]

    static func seed(in context: ModelContext) {
        for name in predefined {
            let normalized = Tag.normalized(name)
            let predicate = #Predicate<Tag> { $0.name == normalized }
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = (try? context.fetchCount(descriptor)) ?? 0
            guard existing == 0 else { continue }

            let tag = Tag(name: normalized, isPredefined: true)
            context.insert(tag)
        }
        try? context.save()
    }
}
