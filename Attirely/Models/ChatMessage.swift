import Foundation

enum ChatRole {
    case user
    case assistant
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var text: String?
    var outfits: [Outfit]
    var wardrobeItems: [ClothingItem]
    var insightNote: String?
    var purchaseSuggestions: [PurchaseSuggestionDTO]
    var isStreaming: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String? = nil,
        outfits: [Outfit] = [],
        wardrobeItems: [ClothingItem] = [],
        insightNote: String? = nil,
        purchaseSuggestions: [PurchaseSuggestionDTO] = [],
        isStreaming: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.outfits = outfits
        self.wardrobeItems = wardrobeItems
        self.insightNote = insightNote
        self.purchaseSuggestions = purchaseSuggestions
        self.isStreaming = isStreaming
        self.timestamp = timestamp
    }
}
