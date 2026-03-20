import Foundation

struct OutfitSuggestionDTO: Codable {
    let name: String
    let occasion: String
    let itemIDs: [String]
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case name, occasion, reasoning
        case itemIDs = "item_ids"
    }
}
