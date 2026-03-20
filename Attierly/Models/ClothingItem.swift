import Foundation
import SwiftData

@Model
final class ClothingItem {
    @Attribute(.unique) var id: UUID

    // AI-detected fields (user-editable)
    var type: String
    var category: String
    var primaryColor: String
    var secondaryColor: String?
    var pattern: String
    var fabricEstimate: String
    var weight: String
    var formality: String
    var season: [String]
    var fit: String?
    var statementLevel: String
    var itemDescription: String

    // User-added fields
    var brand: String?
    var notes: String?

    // Image paths (relative to Documents directory)
    var imagePath: String?
    var sourceImagePath: String?

    // Metadata
    var createdAt: Date
    var updatedAt: Date

    // Original AI values stored as JSON for reference when editing
    var aiOriginalValues: String?

    // Relationships
    var scanSession: ScanSession?
    var outfits: [Outfit] = []

    init(from dto: ClothingItemDTO, sourceImagePath: String? = nil) {
        self.id = dto.id
        self.type = dto.type
        self.category = dto.category
        self.primaryColor = dto.primaryColor
        self.secondaryColor = dto.secondaryColor
        self.pattern = dto.pattern
        self.fabricEstimate = dto.fabricEstimate
        self.weight = dto.weight
        self.formality = dto.formality
        self.season = dto.season
        self.fit = dto.fit
        self.statementLevel = dto.statementLevel
        self.itemDescription = dto.description
        self.sourceImagePath = sourceImagePath
        self.createdAt = Date()
        self.updatedAt = Date()
        self.aiOriginalValues = Self.encodeOriginalValues(dto)
    }

    func originalAIValue(for field: String) -> String? {
        guard let json = aiOriginalValues,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict[field] as? String
    }

    private static func encodeOriginalValues(_ dto: ClothingItemDTO) -> String? {
        let dict: [String: Any] = [
            "type": dto.type,
            "category": dto.category,
            "primaryColor": dto.primaryColor,
            "secondaryColor": dto.secondaryColor as Any,
            "pattern": dto.pattern,
            "fabricEstimate": dto.fabricEstimate,
            "weight": dto.weight,
            "formality": dto.formality,
            "fit": dto.fit as Any,
            "statementLevel": dto.statementLevel,
            "itemDescription": dto.description
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
