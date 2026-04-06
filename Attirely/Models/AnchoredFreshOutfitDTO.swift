import Foundation

struct AnchoredFreshOutfitDTO: Codable {
    let name: String
    let occasion: String
    let reasoning: String
    let suggestedItems: [SuggestedItem]

    struct SuggestedItem: Codable {
        let category: String
        let colorAndFabric: String
        let cutAndFit: String
        let whyItWorks: String

        enum CodingKeys: String, CodingKey {
            case category
            case colorAndFabric = "color_and_fabric"
            case cutAndFit = "cut_and_fit"
            case whyItWorks = "why_it_works"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, occasion, reasoning
        case suggestedItems = "suggested_items"
    }
}
