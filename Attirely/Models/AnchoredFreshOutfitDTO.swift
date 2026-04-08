import Foundation

struct AnchorOutfitResultDTO: Codable {
    let title: String
    let occasion: String
    let items: [Item]
    let stylingNote: String?

    struct Item: Codable {
        let source: String       // "wardrobe" | "suggested"
        let wardrobeItemId: String?
        let category: String
        let description: String
        let whyItWorks: String

        enum CodingKeys: String, CodingKey {
            case source, category, description
            case wardrobeItemId = "wardrobe_item_id"
            case whyItWorks = "why_it_works"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = try c.decode(String.self, forKey: .source)
            wardrobeItemId = try? c.decodeIfPresent(String.self, forKey: .wardrobeItemId)
            category = try c.decode(String.self, forKey: .category)
            description = try c.decode(String.self, forKey: .description)
            whyItWorks = try c.decode(String.self, forKey: .whyItWorks)
        }
    }

    enum CodingKeys: String, CodingKey {
        case title, occasion, items
        case stylingNote = "styling_note"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        occasion = try c.decode(String.self, forKey: .occasion)
        items = (try? c.decodeIfPresent([Item].self, forKey: .items)) ?? []
        stylingNote = try? c.decodeIfPresent(String.self, forKey: .stylingNote)
    }
}
