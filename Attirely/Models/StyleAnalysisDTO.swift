import Foundation

struct StyleModeDTO: Codable {
    let name: String
    let description: String
    let colorPalette: [String]
    let formality: String

    enum CodingKeys: String, CodingKey {
        case name, description, formality
        case colorPalette = "color_palette"
    }
}

struct StyleAnalysisDTO: Codable {
    let overallIdentity: String
    let styleModes: [StyleModeDTO]
    let temporalNotes: String?
    let gapObservations: String?
    let weatherBehavior: String?

    enum CodingKeys: String, CodingKey {
        case overallIdentity = "overall_identity"
        case styleModes = "style_modes"
        case temporalNotes = "temporal_notes"
        case gapObservations = "gap_observations"
        case weatherBehavior = "weather_behavior"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overallIdentity = try container.decode(String.self, forKey: .overallIdentity)
        styleModes = (try? container.decode([StyleModeDTO].self, forKey: .styleModes)) ?? []
        temporalNotes = try container.decodeIfPresent(String.self, forKey: .temporalNotes)
        gapObservations = try container.decodeIfPresent(String.self, forKey: .gapObservations)
        weatherBehavior = try container.decodeIfPresent(String.self, forKey: .weatherBehavior)
    }
}
