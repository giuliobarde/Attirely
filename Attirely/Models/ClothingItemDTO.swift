import Foundation

struct ClothingItemDTO: Codable, Identifiable {
    let id: UUID
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
    var description: String
    var formalityFloor: String?
    var tags: [String]
    var sourceImageIndices: [Int]

    enum CodingKeys: String, CodingKey {
        case type, category, pattern, weight, formality, season, fit, description, tags
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case fabricEstimate = "fabric_estimate"
        case statementLevel = "statement_level"
        case formalityFloor = "formality_floor"
        case sourceImageIndices = "source_image_indices"
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
        self.formalityFloor = try? container.decodeIfPresent(String.self, forKey: .formalityFloor)
        self.tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        self.sourceImageIndices = (try? container.decodeIfPresent([Int].self, forKey: .sourceImageIndices)) ?? [0]
    }
}
