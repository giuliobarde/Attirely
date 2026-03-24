import Foundation

// MARK: - Style Weight

enum StyleWeight: String {
    case high, medium, low
}

// MARK: - Dress Code Strictness

enum DressCodeStrictness {
    case relaxed, moderate, strict
}

// MARK: - OccasionTier

enum OccasionTier: String, CaseIterable, Identifiable {
    case casual = "Casual"
    case smartCasual = "Smart Casual"
    case businessCasual = "Business Casual"
    case business = "Business"
    case cocktail = "Cocktail"
    case formal = "Formal"
    case blackTie = "Black Tie"
    case whiteTie = "White Tie"
    case gymAthletic = "Gym/Athletic"
    case outdoorActive = "Outdoor/Active"

    var id: String { rawValue }

    var formalityLevel: Int {
        switch self {
        case .casual: 0
        case .smartCasual: 1
        case .businessCasual: 2
        case .business: 3
        case .cocktail: 4
        case .formal: 5
        case .blackTie: 6
        case .whiteTie: 7
        case .gymAthletic: 0
        case .outdoorActive: 1
        }
    }

    var dressCodeStrictness: DressCodeStrictness {
        switch self {
        case .casual, .smartCasual, .gymAthletic, .outdoorActive: .relaxed
        case .businessCasual, .business: .moderate
        case .cocktail, .formal, .blackTie, .whiteTie: .strict
        }
    }

    var styleProfileWeight: StyleWeight {
        switch self {
        case .casual, .smartCasual: .high
        case .businessCasual, .business: .medium
        case .cocktail, .formal, .blackTie, .whiteTie, .gymAthletic, .outdoorActive: .low
        }
    }

    var isActivityBased: Bool {
        self == .gymAthletic || self == .outdoorActive
    }

    // MARK: - Filtering Rules

    var allowedFormalityValues: Set<String> {
        switch self {
        case .casual: ["Casual", "Smart Casual"]
        case .smartCasual: ["Casual", "Smart Casual", "Business Casual"]
        case .businessCasual: ["Smart Casual", "Business Casual", "Business"]
        case .business: ["Business Casual", "Business", "Formal"]
        case .formal, .cocktail: ["Business", "Formal"]
        case .blackTie, .whiteTie: ["Formal"]
        case .gymAthletic: ["Casual"]
        case .outdoorActive: ["Casual", "Smart Casual"]
        }
    }

    var excludedTypeKeywords: [String] {
        switch self {
        case .casual:
            []
        case .smartCasual:
            ["flip flop", "croc"]
        case .businessCasual:
            ["flip flop", "croc", "sneaker", "running shoe", "sweatpant", "jogger", "hoodie", "tank top", "crop top"]
        case .business:
            ["flip flop", "croc", "sneaker", "running shoe", "sweatpant", "jogger", "hoodie", "tank top", "crop top", "cargo", "distressed", "ripped"]
        case .formal, .cocktail:
            ["flip flop", "croc", "sneaker", "running shoe", "sweatpant", "jogger", "hoodie", "tank top", "crop top", "cargo", "distressed", "ripped", "t-shirt", "tee", "graphic", "denim", "jean"]
        case .blackTie:
            ["flip flop", "croc", "sneaker", "running shoe", "sweatpant", "jogger", "hoodie", "tank top", "crop top", "cargo", "distressed", "ripped", "t-shirt", "tee", "graphic", "denim", "jean", "polo", "khaki", "chino", "sandal"]
        case .whiteTie:
            ["flip flop", "croc", "sneaker", "running shoe", "sweatpant", "jogger", "hoodie", "tank top", "crop top", "cargo", "distressed", "ripped", "t-shirt", "tee", "graphic", "denim", "jean", "polo", "khaki", "chino", "sandal", "short sleeve", "open collar"]
        case .gymAthletic:
            [] // uses inverted logic via includedTypeKeywords
        case .outdoorActive:
            ["dress shoe", "oxford shoe", "pump", "heel", "loafer", "suit", "blazer", "silk"]
        }
    }

    /// For gym/athletic: items must match one of these keywords OR be a casual Top/Bottom
    var includedTypeKeywords: [String]? {
        switch self {
        case .gymAthletic:
            ["running", "training", "athletic", "sport", "gym", "sneaker", "legging", "jogger", "tank", "shorts", "sweatpant", "hoodie", "track", "zip-up", "trainer"]
        default:
            nil
        }
    }

    /// Fabrics that are hard-excluded for this occasion
    var excludedFabrics: Set<String> {
        switch self {
        case .formal, .cocktail: ["Denim", "Fleece"]
        case .blackTie, .whiteTie: ["Denim", "Fleece"]
        default: []
        }
    }

    // MARK: - Prompt Context

    var dressCodeInstructions: String {
        switch self {
        case .casual:
            "OCCASION: Casual. Relaxed, everyday style. Comfort and self-expression are the priority. No formality constraints."
        case .smartCasual:
            "OCCASION: Smart Casual. Polished but relaxed — think elevated basics. Clean sneakers or loafers, well-fitted jeans or chinos, layered tops. Avoid overly formal or overly athletic items."
        case .businessCasual:
            "OCCASION: Business Casual. Professional but approachable. Collared shirts, structured trousers or dark denim, loafers or clean dress shoes. Avoid athletic wear, graphic prints, and overly casual footwear."
        case .business:
            "OCCASION: Business/Professional. Conservative and polished. Suits or blazer combinations, dress shirts, dress shoes. Avoid casual fabrics, sneakers, and bold patterns."
        case .cocktail:
            "DRESS CODE: Cocktail. Smart, polished, slightly dressy. Dark suits or tailored separates, dress shoes, refined accessories. Avoid denim, sneakers, and casual basics."
        case .formal:
            "DRESS CODE: Formal. Conservative, elegant ensemble. Dark suit or equivalent, dress shirt, dress shoes, tie optional but recommended. Avoid casual fabrics and sporty items."
        case .blackTie:
            "DRESS CODE: Black Tie (Strict). Tuxedo or dark formal suit required. White dress shirt, bow tie or black tie, patent leather or polished dress shoes. Pocket square optional. No casual items, no brown shoes, no loafers."
        case .whiteTie:
            "DRESS CODE: White Tie (Ultra-Formal). The most formal dress code. Black tailcoat, white waistcoat, white bow tie, wing-collar shirt, patent leather shoes. Absolutely no deviations from the dress code."
        case .gymAthletic:
            "OCCASION: Gym/Athletic. Prioritize function, comfort, and mobility. Performance fabrics preferred (moisture-wicking, stretchy). Athletic shoes required. Style is secondary to function."
        case .outdoorActive:
            "OCCASION: Outdoor/Active. Durable, weather-appropriate, comfortable. Prioritize layering, sturdy footwear, and functional fabrics. Avoid delicate or formal items."
        }
    }

    var priorityHierarchy: String {
        switch self {
        case .casual:
            "PRIORITY ORDER: aesthetics > weather appropriateness > personal style > comfort"
        case .smartCasual:
            "PRIORITY ORDER: aesthetics > personal style > weather appropriateness > occasion appropriateness"
        case .businessCasual:
            "PRIORITY ORDER: occasion appropriateness > aesthetics > weather > personal style"
        case .business:
            "PRIORITY ORDER: dress code compliance > occasion > weather > aesthetics > personal style"
        case .cocktail, .formal:
            "PRIORITY ORDER: dress code compliance > occasion > aesthetics > weather > personal style"
        case .blackTie, .whiteTie:
            "PRIORITY ORDER: dress code compliance > occasion > aesthetics > comfort > personal style"
        case .gymAthletic:
            "PRIORITY ORDER: function > comfort > weather > personal style"
        case .outdoorActive:
            "PRIORITY ORDER: function > weather appropriateness > comfort > personal style"
        }
    }

    var styleWeightInstruction: String {
        switch styleProfileWeight {
        case .high:
            "USER STYLE PROFILE — HIGH RELEVANCE: Follow the user's style closely. Personal expression is the primary goal."
        case .medium:
            "USER STYLE PROFILE — MODERATE RELEVANCE: Balance style preferences with occasion appropriateness. When in conflict, prioritize looking appropriate for the setting."
        case .low:
            "USER STYLE PROFILE — LOW RELEVANCE: Dress code compliance takes priority over personal style. Only apply style preferences when choosing between equally appropriate options."
        }
    }

    // MARK: - Picker Grouping

    struct OccasionGroup: Identifiable {
        let label: String
        let items: [OccasionTier]
        var id: String { label }
    }

    static var pickerGroups: [OccasionGroup] {
        [
            OccasionGroup(label: "Everyday", items: [.casual, .smartCasual]),
            OccasionGroup(label: "Work", items: [.businessCasual, .business]),
            OccasionGroup(label: "Dress Code", items: [.cocktail, .formal, .blackTie, .whiteTie]),
            OccasionGroup(label: "Active", items: [.gymAthletic, .outdoorActive])
        ]
    }

    // MARK: - String Mapping

    /// Maps free-form occasion strings (from agent tool calls, legacy data) to an OccasionTier.
    init?(fromString string: String) {
        let normalized = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Direct rawValue match
        if let match = OccasionTier.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            self = match
            return
        }

        // Keyword-based fuzzy matching
        let keywordMap: [(keywords: [String], tier: OccasionTier)] = [
            (["white tie", "whitetie", "white-tie", "ultra formal", "ultra-formal"], .whiteTie),
            (["black tie", "blacktie", "black-tie", "gala", "tuxedo"], .blackTie),
            (["cocktail", "cocktail party", "semi-formal", "semi formal"], .cocktail),
            (["formal", "evening", "ball"], .formal),
            (["business casual", "business-casual", "smart professional"], .businessCasual),
            (["business", "professional", "office", "corporate"], .business),
            (["smart casual", "smart-casual", "elevated casual", "polished casual"], .smartCasual),
            (["gym", "athletic", "workout", "exercise", "training", "fitness"], .gymAthletic),
            (["outdoor", "hiking", "active", "adventure", "trail"], .outdoorActive),
            (["casual", "everyday", "relaxed", "weekend", "laid back", "laid-back"], .casual),
        ]

        for entry in keywordMap {
            for keyword in entry.keywords {
                if normalized.contains(keyword) {
                    self = entry.tier
                    return
                }
            }
        }

        return nil
    }
}

// MARK: - Relaxation Reason

enum RelaxationReason: String {
    case noFormalMatch = "No items matched the required formality level"
    case noTypeMatch = "All items in this category were excluded by type"
    case insufficientItems = "Too few items remained after filtering"
}

// MARK: - Wardrobe Gap

struct WardrobeGap {
    let category: String
    let description: String
    let suggestion: String
}

// MARK: - Filter Result

struct OccasionFilterResult {
    let items: [ClothingItem]
    let occasion: OccasionTier?
    let relaxedCategories: [String: RelaxationReason]
    let isFullyRelaxed: Bool
    let wardrobeGaps: [WardrobeGap]
}

// MARK: - Filter Context (for prompt injection)

struct OccasionFilterContext {
    let tier: OccasionTier
    let styleWeight: StyleWeight
    let wardrobeGaps: [WardrobeGap]
    let relaxedCategories: [String]
}

// MARK: - OccasionFilter

enum OccasionFilter {

    private static let requiredCategories: Set<String> = ["Top", "Bottom", "Footwear"]

    /// Filters wardrobe items based on occasion appropriateness with progressive relaxation.
    static func filterItems(_ items: [ClothingItem], for occasion: OccasionTier?) -> OccasionFilterResult {
        guard let occasion else {
            return OccasionFilterResult(items: items, occasion: nil, relaxedCategories: [:], isFullyRelaxed: false, wardrobeGaps: [])
        }

        // Small wardrobes: skip filtering to avoid crippling the outfit pool
        if items.count < 5 {
            return OccasionFilterResult(items: items, occasion: occasion, relaxedCategories: [:], isFullyRelaxed: true, wardrobeGaps: [])
        }

        // Phase 1: Apply hard filters
        var filtered = items.filter { isItemAllowed($0, for: occasion) }

        // Phase 2: Progressive relaxation per required category
        var relaxedCategories: [String: RelaxationReason] = [:]
        let originalByCategory = Dictionary(grouping: items, by: \.category)
        let filteredByCategory = Dictionary(grouping: filtered, by: \.category)

        for category in requiredCategories {
            let originalCount = originalByCategory[category]?.count ?? 0
            let filteredCount = filteredByCategory[category]?.count ?? 0

            if filteredCount == 0 && originalCount > 0 {
                // Relax: add back all original items for this category
                let restoredItems = originalByCategory[category] ?? []
                filtered.append(contentsOf: restoredItems)

                // Determine reason
                let reason = determineRelaxationReason(
                    originalItems: restoredItems,
                    occasion: occasion
                )
                relaxedCategories[category] = reason
            }
        }

        // Phase 3: If still too few items, fully relax
        if filtered.count < 3 {
            let gaps = generateGaps(relaxedCategories: relaxedCategories, occasion: occasion)
            return OccasionFilterResult(items: items, occasion: occasion, relaxedCategories: relaxedCategories, isFullyRelaxed: true, wardrobeGaps: gaps)
        }

        // Phase 4: Generate gap notes
        let gaps = generateGaps(relaxedCategories: relaxedCategories, occasion: occasion)

        return OccasionFilterResult(items: filtered, occasion: occasion, relaxedCategories: relaxedCategories, isFullyRelaxed: false, wardrobeGaps: gaps)
    }

    // MARK: - Item Filtering

    private static func isItemAllowed(_ item: ClothingItem, for occasion: OccasionTier) -> Bool {
        // Activity-based tiers use inverted logic
        if let includedKeywords = occasion.includedTypeKeywords {
            return isItemIncludedForActivity(item, keywords: includedKeywords, occasion: occasion)
        }

        // Standard filtering: formality + type keywords + fabric
        let formalityAllowed = occasion.allowedFormalityValues.contains(item.formality)
        let typeAllowed = !isTypeExcluded(item.type, keywords: occasion.excludedTypeKeywords)
        let fabricAllowed = !occasion.excludedFabrics.contains(item.fabricEstimate)

        return formalityAllowed && typeAllowed && fabricAllowed
    }

    /// For activity-based tiers (gym): items must match included keywords OR be casual basics
    private static func isItemIncludedForActivity(_ item: ClothingItem, keywords: [String], occasion: OccasionTier) -> Bool {
        let lowType = item.type.lowercased()

        // Match any included keyword
        for keyword in keywords {
            if lowType.contains(keyword) { return true }
        }

        // Allow casual tops and bottoms as fallback (e.g., plain "T-Shirt" for gym)
        let casualBasicCategories: Set<String> = ["Top", "Bottom", "Full Body"]
        if casualBasicCategories.contains(item.category) && occasion.allowedFormalityValues.contains(item.formality) {
            return true
        }

        return false
    }

    private static func isTypeExcluded(_ type: String, keywords: [String]) -> Bool {
        let lowType = type.lowercased()
        return keywords.contains { lowType.contains($0) }
    }

    private static func determineRelaxationReason(originalItems: [ClothingItem], occasion: OccasionTier) -> RelaxationReason {
        // Check if any items would pass formality alone
        let formalityPassCount = originalItems.filter { occasion.allowedFormalityValues.contains($0.formality) }.count
        if formalityPassCount == 0 {
            return .noFormalMatch
        }
        return .noTypeMatch
    }

    // MARK: - Gap Generation

    private static func generateGaps(relaxedCategories: [String: RelaxationReason], occasion: OccasionTier) -> [WardrobeGap] {
        relaxedCategories.map { category, _ in
            gapForCategory(category, occasion: occasion)
        }.sorted { $0.category < $1.category }
    }

    private static func gapForCategory(_ category: String, occasion: OccasionTier) -> WardrobeGap {
        switch (category, occasion) {
        // Footwear gaps
        case ("Footwear", .blackTie), ("Footwear", .whiteTie):
            WardrobeGap(
                category: category,
                description: "No black-tie footwear found in your wardrobe.",
                suggestion: "Consider investing in patent leather oxfords or formal pumps."
            )
        case ("Footwear", .formal), ("Footwear", .cocktail):
            WardrobeGap(
                category: category,
                description: "No formal footwear found in your wardrobe.",
                suggestion: "Consider adding dress shoes, oxfords, or heeled pumps."
            )
        case ("Footwear", .business), ("Footwear", .businessCasual):
            WardrobeGap(
                category: category,
                description: "No business-appropriate footwear found.",
                suggestion: "Consider adding loafers, dress shoes, or polished boots."
            )
        case ("Footwear", .gymAthletic):
            WardrobeGap(
                category: category,
                description: "No athletic footwear found in your wardrobe.",
                suggestion: "Consider adding training shoes or running shoes."
            )
        case ("Footwear", .outdoorActive):
            WardrobeGap(
                category: category,
                description: "No outdoor footwear found in your wardrobe.",
                suggestion: "Consider adding hiking boots or trail shoes."
            )

        // Top gaps
        case ("Top", .blackTie), ("Top", .whiteTie):
            WardrobeGap(
                category: category,
                description: "No formal shirts found in your wardrobe.",
                suggestion: "Consider adding a white dress shirt or tuxedo shirt."
            )
        case ("Top", .formal), ("Top", .cocktail):
            WardrobeGap(
                category: category,
                description: "Limited formal tops in your wardrobe.",
                suggestion: "Consider adding dress shirts or structured blouses."
            )
        case ("Top", .business), ("Top", .businessCasual):
            WardrobeGap(
                category: category,
                description: "Limited business-appropriate tops.",
                suggestion: "Consider adding collared shirts, blouses, or structured knits."
            )
        case ("Top", .gymAthletic):
            WardrobeGap(
                category: category,
                description: "No athletic tops found.",
                suggestion: "Consider adding performance t-shirts or tank tops."
            )

        // Bottom gaps
        case ("Bottom", .blackTie), ("Bottom", .whiteTie):
            WardrobeGap(
                category: category,
                description: "No formal trousers found in your wardrobe.",
                suggestion: "Consider adding formal dress pants or a tuxedo."
            )
        case ("Bottom", .formal), ("Bottom", .cocktail):
            WardrobeGap(
                category: category,
                description: "Limited formal bottoms in your wardrobe.",
                suggestion: "Consider adding tailored trousers or a formal skirt."
            )
        case ("Bottom", .business), ("Bottom", .businessCasual):
            WardrobeGap(
                category: category,
                description: "Limited business-appropriate bottoms.",
                suggestion: "Consider adding dress pants, tailored chinos, or a pencil skirt."
            )
        case ("Bottom", .gymAthletic):
            WardrobeGap(
                category: category,
                description: "No athletic bottoms found.",
                suggestion: "Consider adding gym shorts, leggings, or joggers."
            )

        // Default fallback
        default:
            WardrobeGap(
                category: category,
                description: "Limited \(occasion.rawValue.lowercased())-appropriate \(category.lowercased()) items.",
                suggestion: "Consider expanding your \(category.lowercased()) options for \(occasion.rawValue.lowercased()) occasions."
            )
        }
    }

    // MARK: - Prompt Helpers

    /// Builds a prompt context string describing wardrobe limitations for Claude.
    static func wardrobeLimitationPrompt(from result: OccasionFilterResult) -> String? {
        guard !result.wardrobeGaps.isEmpty else { return nil }

        var lines = ["WARDROBE LIMITATIONS:"]
        lines.append("The user's wardrobe lacks ideal items for this occasion. Compromises were made in filtering:")
        for gap in result.wardrobeGaps {
            lines.append("- \(gap.category): \(gap.description)")
        }
        lines.append("Work with the available items and select the most appropriate options. Acknowledge any compromises in your reasoning.")
        lines.append("Include wardrobe gap suggestions in the \"wardrobe_gaps\" field of your response.")
        return lines.joined(separator: "\n")
    }

    /// Builds an OccasionFilterContext for passing to AnthropicService.
    static func buildFilterContext(from result: OccasionFilterResult) -> OccasionFilterContext? {
        guard let occasion = result.occasion else { return nil }
        return OccasionFilterContext(
            tier: occasion,
            styleWeight: occasion.styleProfileWeight,
            wardrobeGaps: result.wardrobeGaps,
            relaxedCategories: Array(result.relaxedCategories.keys)
        )
    }

    /// Merges client-side gap descriptions with AI-returned gap strings, deduplicating.
    static func mergeGaps(clientSide: [WardrobeGap], aiSide: [String]) -> [String] {
        var merged: [String] = []

        // Client-side gaps: combine description + suggestion
        for gap in clientSide {
            merged.append("\(gap.description) \(gap.suggestion)")
        }

        // AI gaps: add if not substantially overlapping with client gaps
        for aiGap in aiSide {
            let aiLower = aiGap.lowercased()
            let isDuplicate = merged.contains { existing in
                let existingLower = existing.lowercased()
                // Simple overlap check: if they share a significant substring
                return existingLower.contains(aiLower) || aiLower.contains(existingLower)
            }
            if !isDuplicate {
                merged.append(aiGap)
            }
        }

        return merged
    }
}
