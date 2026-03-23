import Foundation

struct OutfitSuggestionDTO: Codable {
    let name: String
    let occasion: String
    let itemIDs: [String]
    let reasoning: String
    let spokenSummary: String?

    enum CodingKeys: String, CodingKey {
        case name, occasion, reasoning
        case itemIDs = "item_ids"
        case spokenSummary = "spoken_summary"
    }
}
