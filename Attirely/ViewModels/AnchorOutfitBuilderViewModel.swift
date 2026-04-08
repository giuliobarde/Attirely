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

    // Results
    var generatedOutfits: [AnchorOutfitResultDTO] = []
    // Wardrobe candidates retained for UUID → ClothingItem lookup and saving
    var wardrobeCandidates: [ClothingItem] = []
    // Tracks which outfit indices have been saved (wardrobe mode only)
    var savedIndices: Set<Int> = []

    var hasResult: Bool { !generatedOutfits.isEmpty }

    init(anchorItem: ClothingItem) {
        self.anchorItem = anchorItem
    }

    func clearResult() {
        generatedOutfits = []
        wardrobeCandidates = []
        savedIndices = []
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

        var candidateItems: [ClothingItem] = []

        if useWardrobe {
            // Filter and score wardrobe candidates
            let filterResult = OccasionFilter.filterItems(allItems, for: selectedOccasionTier)
            let scorerConfig = RelevanceScorerConfig(
                occasion: selectedOccasionTier,
                season: nil,
                currentTemp: nil,
                observations: [],
                allOutfits: existingOutfits
            )
            var scored = RelevanceScorer.selectCandidates(from: filterResult.items, config: scorerConfig)
            // Always include anchor even if filtered out
            if !scored.contains(where: { $0.item.id == anchorItem.id }) {
                scored.append(ScoredItem(item: anchorItem, score: 1.0))
            }
            candidateItems = scored.map(\.item)
            wardrobeCandidates = candidateItems
        }

        Task {
            do {
                let results = try await AnthropicService.generateAnchoredOutfits(
                    anchor: anchorItem,
                    wardrobeItems: candidateItems,
                    occasion: selectedOccasionTier?.rawValue,
                    weatherContext: weatherContext,
                    styleSummary: styleSummary,
                    styleMode: userProfile?.styleMode,
                    styleDirection: userProfile?.styleDirection
                )
                self.generatedOutfits = results
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isGenerating = false
        }
    }

    func wardrobeItems(for outfit: AnchorOutfitResultDTO) -> [ClothingItem] {
        outfit.items.compactMap { item in
            guard item.source == "wardrobe", let idString = item.wardrobeItemId else { return nil }
            return wardrobeCandidates.first { $0.id.uuidString == idString }
        }
    }

    func canSave(_ outfit: AnchorOutfitResultDTO) -> Bool {
        useWardrobe && !wardrobeItems(for: outfit).isEmpty
    }

    func saveOutfit(
        at index: Int,
        modelContext: ModelContext,
        weatherSnapshot: WeatherSnapshot?
    ) {
        guard index < generatedOutfits.count else { return }
        let result = generatedOutfits[index]
        let items = wardrobeItems(for: result)
        guard !items.isEmpty else { return }

        let outfit = Outfit(
            name: result.title,
            occasion: result.occasion,
            reasoning: result.stylingNote,
            isAIGenerated: true,
            items: items
        )

        if let snapshot = weatherSnapshot {
            outfit.weatherTempAtCreation = snapshot.current.temperature
            outfit.weatherFeelsLikeAtCreation = snapshot.current.feelsLike
        }
        outfit.monthAtCreation = Calendar.current.component(.month, from: Date())

        modelContext.insert(outfit)
        try? modelContext.save()
        savedIndices.insert(index)
    }
}
