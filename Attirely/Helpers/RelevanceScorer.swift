import Foundation

// MARK: - Scored Item

struct ScoredItem {
    let item: ClothingItem
    let score: Double
}

// MARK: - Scorer Configuration

struct RelevanceScorerConfig {
    let occasion: OccasionTier?
    let season: String?
    let currentTemp: Double?
    let observations: [AgentObservation]
    let allOutfits: [Outfit]
}

// MARK: - Relevance Scorer

enum RelevanceScorer {

    // MARK: - Weights

    private static let outfitFrequencyWeight = 0.25
    private static let favoriteWeight = 0.20
    private static let formalityWeight = 0.20
    private static let observationWeight = 0.15
    private static let seasonalWeight = 0.10
    private static let usageWeight = 0.10

    private static let targetPoolSize = 35
    private static let minPerRequiredCategory = 4
    private static let requiredCategories: Set<String> = ["Top", "Bottom", "Footwear"]

    // MARK: - Public API

    /// Score all items and return a category-balanced candidate pool.
    static func selectCandidates(
        from items: [ClothingItem],
        config: RelevanceScorerConfig
    ) -> [ScoredItem] {
        // If pool is already small enough, score but return all
        guard items.count > targetPoolSize else {
            return items.map { score(item: $0, config: config) }
                .sorted { $0.score > $1.score }
        }

        let scored = items.map { score(item: $0, config: config) }
        return balancedSelection(from: scored)
    }

    /// Score a single item against the current context.
    static func score(
        item: ClothingItem,
        config: RelevanceScorerConfig
    ) -> ScoredItem {
        let freq = outfitFrequencyScore(item: item, occasion: config.occasion, allOutfits: config.allOutfits)
        let fav = favoriteBonus(item: item, allOutfits: config.allOutfits)
        let form = formalityScore(item: item, occasion: config.occasion)
        let obs = observationScore(item: item, observations: config.observations, occasion: config.occasion)
        let season = seasonalScore(item: item, season: config.season)
        let usage = usageScore(item: item)

        let total = freq * outfitFrequencyWeight
            + fav * favoriteWeight
            + form * formalityWeight
            + obs * observationWeight
            + season * seasonalWeight
            + usage * usageWeight

        return ScoredItem(item: item, score: total)
    }

    // MARK: - Scoring Components (0.0 – 1.0)

    /// How often this item appears in outfits for similar occasions.
    private static func outfitFrequencyScore(
        item: ClothingItem,
        occasion: OccasionTier?,
        allOutfits: [Outfit]
    ) -> Double {
        guard !allOutfits.isEmpty else { return 0.5 }

        let relevantOutfits: [Outfit]
        if let occasion {
            let targetLevel = occasion.formalityLevel
            relevantOutfits = allOutfits.filter { outfit in
                guard let outfitOccasion = outfit.occasion,
                      let outfitTier = OccasionTier(fromString: outfitOccasion)
                else { return true } // include outfits with no occasion
                return abs(outfitTier.formalityLevel - targetLevel) <= 1
            }
        } else {
            relevantOutfits = allOutfits
        }

        guard !relevantOutfits.isEmpty else { return 0.5 }

        let appearances = relevantOutfits.filter { outfit in
            outfit.items.contains { $0.id == item.id }
        }.count

        // Normalize: 3+ appearances = 1.0
        return min(Double(appearances) / 3.0, 1.0)
    }

    /// Strong positive signal if item appears in favorited outfits.
    private static func favoriteBonus(
        item: ClothingItem,
        allOutfits: [Outfit]
    ) -> Double {
        let favoritedOutfits = allOutfits.filter(\.isFavorite)
        guard !favoritedOutfits.isEmpty else { return 0.5 }

        let appearances = favoritedOutfits.filter { outfit in
            outfit.items.contains { $0.id == item.id }
        }.count

        // Any appearance in favorites = high score
        if appearances >= 2 { return 1.0 }
        if appearances == 1 { return 0.8 }
        return 0.3
    }

    /// How well the item's formality aligns with the occasion.
    private static func formalityScore(
        item: ClothingItem,
        occasion: OccasionTier?
    ) -> Double {
        guard let occasion else { return 0.5 }

        if occasion.allowedFormalityValues.contains(item.formality) {
            return 1.0
        }

        // Partial credit for adjacent formality levels
        let formalityLevels = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]
        guard let itemIndex = formalityLevels.firstIndex(of: item.formality) else { return 0.3 }

        let targetFormalities = occasion.allowedFormalityValues
        let targetIndices = targetFormalities.compactMap { formalityLevels.firstIndex(of: $0) }
        guard let closestTarget = targetIndices.min(by: { abs($0 - itemIndex) < abs($1 - itemIndex) }) else { return 0.3 }

        let distance = abs(itemIndex - closestTarget)
        switch distance {
        case 0: return 1.0
        case 1: return 0.6
        case 2: return 0.3
        default: return 0.1
        }
    }

    /// Factor in agent observations: positive boosts, negative penalizes.
    private static func observationScore(
        item: ClothingItem,
        observations: [AgentObservation],
        occasion: OccasionTier?
    ) -> Double {
        guard !observations.isEmpty else { return 0.5 }

        var score = 0.5
        let itemWords = Set([
            item.type.lowercased(),
            item.primaryColor.lowercased(),
            item.category.lowercased(),
            item.fabricEstimate.lowercased()
        ])

        for observation in observations {
            let obsWords = Set(
                observation.pattern.lowercased()
                    .components(separatedBy: .alphanumerics.inverted)
                    .filter { $0.count > 1 }
            )

            let overlap = itemWords.intersection(obsWords)
            guard !overlap.isEmpty else { continue }

            // Check occasion relevance
            var relevanceMultiplier = 1.0
            if let obsContext = observation.occasionContext,
               let occasion {
                let occasionName = occasion.rawValue.lowercased()
                if obsContext.lowercased().contains(occasionName) {
                    relevanceMultiplier = 1.5
                } else {
                    relevanceMultiplier = 0.5
                }
            }

            let impact = 0.1 * relevanceMultiplier * Double(min(observation.occurrenceCount, 5))
            switch observation.signal {
            case .positive: score += impact
            case .negative: score -= impact
            }
        }

        return max(0.0, min(1.0, score))
    }

    /// Seasonal match with current season.
    private static func seasonalScore(
        item: ClothingItem,
        season: String?
    ) -> Double {
        guard let season else { return 0.5 }

        if item.season.contains(season) {
            return 1.0
        }

        // All-season items get partial credit
        if item.season.count == 4 {
            return 0.7
        }

        return 0.2
    }

    /// Slight penalty for items never used in any outfit.
    private static func usageScore(item: ClothingItem) -> Double {
        if !item.outfits.isEmpty {
            return 1.0
        }

        // New items (< 30 days old) get benefit of the doubt
        let age = Date().timeIntervalSince(item.createdAt)
        if age < 30 * 24 * 60 * 60 {
            return 0.7
        }

        return 0.3
    }

    // MARK: - Balanced Selection

    /// Select items ensuring minimum coverage per required category.
    private static func balancedSelection(from scored: [ScoredItem]) -> [ScoredItem] {
        let grouped = Dictionary(grouping: scored, by: { $0.item.category })
        var selected: [ScoredItem] = []
        var selectedIDs: Set<UUID> = []

        // First pass: guarantee minimum per required category
        for category in requiredCategories {
            let categoryItems = (grouped[category] ?? []).sorted { $0.score > $1.score }
            let toTake = categoryItems.prefix(minPerRequiredCategory)
            for item in toTake {
                if selectedIDs.insert(item.item.id).inserted {
                    selected.append(item)
                }
            }
        }

        // Second pass: fill remaining slots from all categories by score
        let remaining = scored
            .filter { !selectedIDs.contains($0.item.id) }
            .sorted { $0.score > $1.score }

        for item in remaining {
            if selected.count >= targetPoolSize { break }
            if selectedIDs.insert(item.item.id).inserted {
                selected.append(item)
            }
        }

        return selected.sorted { $0.score > $1.score }
    }
}
