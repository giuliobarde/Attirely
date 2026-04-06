import SwiftUI
import SwiftData

@Observable
class AnchorOutfitBuilderViewModel {
    let anchorItem: ClothingItem

    // Config — reset to defaults on each init
    var useWardrobe: Bool = true
    var selectedOccasionTier: OccasionTier? = nil

    // UI state
    var isGenerating: Bool = false
    var errorMessage: String? = nil

    // "Use wardrobe" result
    var wardrobeOutfitSuggestion: OutfitSuggestionDTO? = nil
    var matchedWardrobeItems: [ClothingItem] = []
    var gapSuggestions: [String] = []

    // "Start fresh" result
    var freshOutfit: AnchoredFreshOutfitDTO? = nil

    var hasResult: Bool { wardrobeOutfitSuggestion != nil || freshOutfit != nil }

    init(anchorItem: ClothingItem) {
        self.anchorItem = anchorItem
    }

    func clearResult() {
        wardrobeOutfitSuggestion = nil
        matchedWardrobeItems = []
        gapSuggestions = []
        freshOutfit = nil
        errorMessage = nil
    }

    func generate(
        allItems: [ClothingItem],
        userProfile: UserProfile?,
        weatherContext: String?,
        styleSummary: String?,
        existingOutfits: [Outfit]
    ) {
        isGenerating = true
        clearResult()

        if useWardrobe {
            generateUsingWardrobe(
                allItems: allItems,
                userProfile: userProfile,
                weatherContext: weatherContext,
                styleSummary: styleSummary,
                existingOutfits: existingOutfits
            )
        } else {
            generateFresh(
                userProfile: userProfile,
                weatherContext: weatherContext,
                styleSummary: styleSummary
            )
        }
    }

    private func generateUsingWardrobe(
        allItems: [ClothingItem],
        userProfile: UserProfile?,
        weatherContext: String?,
        styleSummary: String?,
        existingOutfits: [Outfit]
    ) {
        // Apply occasion-based filtering
        let filterResult = OccasionFilter.filterItems(allItems, for: selectedOccasionTier)
        let filterContext = OccasionFilter.buildFilterContext(from: filterResult)

        // Score candidates
        let scorerConfig = RelevanceScorerConfig(
            occasion: selectedOccasionTier,
            season: nil,
            currentTemp: nil,
            observations: [],
            allOutfits: existingOutfits
        )
        var scoredItems = RelevanceScorer.selectCandidates(from: filterResult.items, config: scorerConfig)

        // Always ensure anchor item is in the candidate list
        let anchorID = anchorItem.id
        if !scoredItems.contains(where: { $0.item.id == anchorID }) {
            scoredItems.append(ScoredItem(item: anchorItem, score: 1.0))
        }

        let candidateItems = scoredItems.map(\.item)
        var relevanceHints = Dictionary(uniqueKeysWithValues: scoredItems.map { ($0.item.id, $0.score) })
        relevanceHints[anchorID] = 1.0

        let existingItemSets = existingOutfits.map { outfit in
            outfit.items.map { $0.id.uuidString }.sorted()
        }

        let mustInclude: Set<String> = [anchorID.uuidString]

        Task {
            do {
                let suggestions = try await AnthropicService.generateOutfits(
                    from: candidateItems,
                    occasion: selectedOccasionTier?.rawValue,
                    season: nil,
                    weatherContext: weatherContext,
                    comfortPreferences: StyleContextHelper.comfortPreferencesString(from: userProfile),
                    styleSummary: styleSummary,
                    filterContext: filterContext,
                    existingOutfitItemSets: existingItemSets,
                    availableTagNames: [],
                    observationContext: nil,
                    itemRelevanceHints: relevanceHints,
                    mustIncludeItemIDs: mustInclude,
                    styleMode: userProfile?.styleMode,
                    styleDirection: userProfile?.styleDirection
                )

                guard let suggestion = suggestions.first else {
                    self.errorMessage = "No outfit could be generated. Try a different occasion or add more items."
                    self.isGenerating = false
                    return
                }

                let matched = candidateItems.filter { suggestion.itemIDs.contains($0.id.uuidString) }
                guard matched.count >= min(3, suggestion.itemIDs.count) else {
                    self.errorMessage = "AI suggested items that couldn't be matched. Try again."
                    self.isGenerating = false
                    return
                }

                self.wardrobeOutfitSuggestion = suggestion
                self.matchedWardrobeItems = matched
                self.gapSuggestions = suggestion.wardrobeGaps
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isGenerating = false
        }
    }

    private func generateFresh(
        userProfile: UserProfile?,
        weatherContext: String?,
        styleSummary: String?
    ) {
        Task {
            do {
                let result = try await AnthropicService.generateAnchoredFreshOutfit(
                    anchor: anchorItem,
                    occasion: selectedOccasionTier?.rawValue,
                    weatherContext: weatherContext,
                    styleSummary: styleSummary,
                    styleMode: userProfile?.styleMode,
                    styleDirection: userProfile?.styleDirection
                )
                self.freshOutfit = result
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isGenerating = false
        }
    }

    func saveOutfit(modelContext: ModelContext, weatherSnapshot: WeatherSnapshot?) {
        guard let suggestion = wardrobeOutfitSuggestion, !matchedWardrobeItems.isEmpty else { return }

        let outfit = Outfit(
            name: suggestion.name,
            occasion: suggestion.occasion,
            reasoning: suggestion.reasoning,
            isAIGenerated: true,
            items: matchedWardrobeItems
        )

        if let snapshot = weatherSnapshot {
            outfit.weatherTempAtCreation = snapshot.current.temperature
            outfit.weatherFeelsLikeAtCreation = snapshot.current.feelsLike
        }
        outfit.monthAtCreation = Calendar.current.component(.month, from: Date())

        if !gapSuggestions.isEmpty {
            outfit.wardrobeGaps = Outfit.encodeGaps(gapSuggestions)
        }

        modelContext.insert(outfit)
        try? modelContext.save()
    }
}
