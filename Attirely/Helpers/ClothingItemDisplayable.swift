protocol ClothingItemDisplayable {
    var type: String { get }
    var category: String { get }
    var primaryColor: String { get }
    var secondaryColor: String? { get }
    var pattern: String { get }
    var fabricEstimate: String { get }
    var weight: String { get }
    var formality: String { get }
    var season: [String] { get }
    var fit: String? { get }
    var statementLevel: String { get }
    var displayDescription: String { get }
}

extension ClothingItemDTO: ClothingItemDisplayable {
    var displayDescription: String { description }
}

extension ClothingItem: ClothingItemDisplayable {
    var displayDescription: String { itemDescription }
}
