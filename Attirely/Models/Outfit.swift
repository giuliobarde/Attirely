import Foundation
import SwiftData

@Model
final class Outfit {
    @Attribute(.unique) var id: UUID

    var name: String?
    var occasion: String?
    var reasoning: String?
    var isAIGenerated: Bool
    var isFavorite: Bool
    var createdAt: Date

    // Weather snapshot at creation/favorite time
    var weatherTempAtCreation: Double?
    var weatherFeelsLikeAtCreation: Double?
    var seasonAtCreation: String?
    var monthAtCreation: Int?

    // Siri integration
    var lastSuggestedBySiriAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \ClothingItem.outfits)
    var items: [ClothingItem]

    @Relationship
    var tags: [Tag] = []

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let occasion, !occasion.isEmpty { return occasion }
        return "Outfit from \(createdAt.formatted(.dateTime.month().day()))"
    }

    init(
        name: String? = nil,
        occasion: String? = nil,
        reasoning: String? = nil,
        isAIGenerated: Bool = false,
        items: [ClothingItem] = [],
        tags: [Tag] = []
    ) {
        self.id = UUID()
        self.name = name
        self.occasion = occasion
        self.reasoning = reasoning
        self.isAIGenerated = isAIGenerated
        self.isFavorite = false
        self.createdAt = Date()
        self.items = items
        self.tags = tags
    }
}
