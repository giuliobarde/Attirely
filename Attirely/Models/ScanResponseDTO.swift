import Foundation

struct ScanResponseDTO: Codable {
    let items: [ClothingItemDTO]
    let outfit: ScanOutfitSuggestionDTO?
}

struct ScanOutfitSuggestionDTO: Codable {
    var name: String
    var occasion: String
    var reasoning: String
}
