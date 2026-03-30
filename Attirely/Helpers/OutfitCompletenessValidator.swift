import Foundation

enum OutfitCompletenessValidator {
    enum Result {
        case valid
        case validMissingFootwear
        case invalid
    }

    static func validate(categories: [String]) -> Result {
        let categorySet = Set(categories)
        let hasTop = categorySet.contains("Top")
        let hasBottom = categorySet.contains("Bottom")
        let hasFullBody = categorySet.contains("Full Body")
        let hasFootwear = categorySet.contains("Footwear")

        let hasValidCombo = (hasTop && hasBottom) || hasFullBody
        guard hasValidCombo else { return .invalid }

        return hasFootwear ? .valid : .validMissingFootwear
    }
}
