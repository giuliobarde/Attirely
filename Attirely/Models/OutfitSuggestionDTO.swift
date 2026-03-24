import Foundation

struct OutfitSuggestionDTO: Codable {
    let name: String
    let occasion: String
    let itemIDs: [String]
    let reasoning: String
    let spokenSummary: String?
    let tags: [String]
    let wardrobeGaps: [String]

    enum CodingKeys: String, CodingKey {
        case name, occasion, reasoning, tags
        case itemIDs = "item_ids"
        case spokenSummary = "spoken_summary"
        case wardrobeGaps = "wardrobe_gaps"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        occasion = try container.decode(String.self, forKey: .occasion)
        itemIDs = try container.decode([String].self, forKey: .itemIDs)
        reasoning = try container.decode(String.self, forKey: .reasoning)
        spokenSummary = try container.decodeIfPresent(String.self, forKey: .spokenSummary)
        tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        wardrobeGaps = (try? container.decodeIfPresent([String].self, forKey: .wardrobeGaps)) ?? []
    }
}
