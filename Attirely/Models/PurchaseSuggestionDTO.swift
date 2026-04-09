import Foundation

struct PurchaseSuggestionDTO: Codable, Identifiable {
    var id: UUID = UUID()
    let category: String
    let description: String
    let styleNote: String
    let pairsWith: [String]
    let wardrobeCompatibilityCount: Int

    enum CodingKeys: String, CodingKey {
        case category, description
        case styleNote = "style_note"
        case pairsWith = "pairs_with"
        case wardrobeCompatibilityCount = "wardrobe_compatibility_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        category = try c.decode(String.self, forKey: .category)
        description = try c.decode(String.self, forKey: .description)
        styleNote = try c.decode(String.self, forKey: .styleNote)
        pairsWith = (try? c.decodeIfPresent([String].self, forKey: .pairsWith)) ?? []
        wardrobeCompatibilityCount = (try? c.decodeIfPresent(Int.self, forKey: .wardrobeCompatibilityCount)) ?? 0
    }
}
