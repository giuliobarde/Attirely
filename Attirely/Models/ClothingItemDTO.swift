import Foundation

struct ClothingItemDTO: Codable, Identifiable {
    let id: UUID
    let type: String
    let category: String
    let primaryColor: String
    let secondaryColor: String?
    let pattern: String
    let fabricEstimate: String
    let weight: String
    let formality: String
    let season: [String]
    let fit: String?
    let statementLevel: String
    let description: String
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case type, category, pattern, weight, formality, season, fit, description, tags
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case fabricEstimate = "fabric_estimate"
        case statementLevel = "statement_level"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.type = try container.decode(String.self, forKey: .type)
        self.category = try container.decode(String.self, forKey: .category)
        self.primaryColor = try container.decode(String.self, forKey: .primaryColor)
        self.secondaryColor = try container.decodeIfPresent(String.self, forKey: .secondaryColor)
        self.pattern = try container.decode(String.self, forKey: .pattern)
        self.fabricEstimate = try container.decode(String.self, forKey: .fabricEstimate)
        self.weight = try container.decode(String.self, forKey: .weight)
        self.formality = try container.decode(String.self, forKey: .formality)
        self.season = try container.decode([String].self, forKey: .season)
        self.fit = try container.decodeIfPresent(String.self, forKey: .fit)
        self.statementLevel = try container.decode(String.self, forKey: .statementLevel)
        self.description = try container.decode(String.self, forKey: .description)
        self.tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }
}
