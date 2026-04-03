import SwiftUI
import SwiftData

@Observable
class OutfitViewModel {
    // List filtering
    var showFavoritesOnly = false
    var selectedTagIDs: Set<PersistentIdentifier> = []

    // Bulk-tag selection mode
    var isSelecting = false
    var selectedOutfitIDs: Set<PersistentIdentifier> = []

    // AI generation context
    var selectedOccasionTier: OccasionTier?
    var selectedSeason: String?

    var selectedOccasion: String? { selectedOccasionTier?.rawValue }

    // AI generation state
    var isGenerating = false
    var errorMessage: String?
    var generatedOutfits: [Outfit] = []
    var showGeneratedResults = false

    // Manual creation state
    var manualSelectedItems: Set<PersistentIdentifier> = []
    var manualOutfitName = ""

    // Sheet presentation
    var isShowingGenerateSheet = false
    var isShowingItemPicker = false
    var isShowingBulkTagEdit = false
    var isShowingDeleteConfirmation = false

    var modelContext: ModelContext?
    var weatherViewModel: WeatherViewModel?
    var userProfile: UserProfile?
    var styleSummaryText: String?
    var styleViewModel: StyleViewModel?

    // MARK: - List

    func filteredOutfits(from outfits: [Outfit]) -> [Outfit] {
        var result = outfits
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        if !selectedTagIDs.isEmpty {
            result = result.filter { outfit in
                selectedTagIDs.allSatisfy { tagID in
                    outfit.tags.contains { $0.persistentModelID == tagID }
                }
            }
        }
        return result
    }

    // MARK: - Favorites

    func toggleFavorite(_ outfit: Outfit) {
        outfit.isFavorite.toggle()
        // Backfill weather snapshot when favoriting if not already captured
        if outfit.isFavorite, outfit.weatherTempAtCreation == nil,
           let snapshot = weatherViewModel?.snapshot {
            outfit.weatherTempAtCreation = snapshot.current.temperature
            outfit.weatherFeelsLikeAtCreation = snapshot.current.feelsLike
            outfit.seasonAtCreation = weatherViewModel?.suggestedSeason
            outfit.monthAtCreation = outfit.monthAtCreation ?? Calendar.current.component(.month, from: Date())
        }
        try? modelContext?.save()
        if outfit.isFavorite {
            notifyStyleAnalysis()
        }
    }

    // MARK: - Delete

    func deleteOutfit(_ outfit: Outfit) {
        guard let modelContext else { return }
        modelContext.delete(outfit)
        try? modelContext.save()
    }

    // MARK: - Manual Creation

    func toggleItemSelection(_ item: ClothingItem) {
        if manualSelectedItems.contains(item.persistentModelID) {
            manualSelectedItems.remove(item.persistentModelID)
        } else {
            manualSelectedItems.insert(item.persistentModelID)
        }
    }

    func isItemSelected(_ item: ClothingItem) -> Bool {
        manualSelectedItems.contains(item.persistentModelID)
    }

    func saveManualOutfit(from allItems: [ClothingItem]) {
        guard let modelContext else { return }
        let selected = allItems.filter { manualSelectedItems.contains($0.persistentModelID) }
        guard !selected.isEmpty else { return }

        let outfit = Outfit(
            name: manualOutfitName.isEmpty ? nil : manualOutfitName,
            isAIGenerated: false,
            items: selected
        )
        captureWeatherSnapshot(on: outfit)
        modelContext.insert(outfit)
        try? modelContext.save()
        notifyStyleAnalysis()

        resetManualCreation()
    }

    func resetManualCreation() {
        manualSelectedItems = []
        manualOutfitName = ""
        isShowingItemPicker = false
    }

    // MARK: - AI Generation

    func generateOutfits(from allItems: [ClothingItem]) {
        guard let modelContext else { return }
        isGenerating = true
        errorMessage = nil

        // Apply occasion-based filtering
        let filterResult = OccasionFilter.filterItems(allItems, for: selectedOccasionTier)
        let filterContext = OccasionFilter.buildFilterContext(from: filterResult)

        // Score and select candidate items for token efficiency
        let summaryDescriptor = FetchDescriptor<StyleSummary>()
        let summary = (try? modelContext.fetch(summaryDescriptor))?.first
        let observations = summary?.activeObservations ?? []

        let existingOutfits = (try? modelContext.fetch(FetchDescriptor<Outfit>())) ?? []

        let scorerConfig = RelevanceScorerConfig(
            occasion: selectedOccasionTier,
            season: selectedSeason,
            currentTemp: weatherViewModel?.snapshot?.current.temperature,
            observations: observations,
            allOutfits: existingOutfits
        )
        let scoredItems = RelevanceScorer.selectCandidates(from: filterResult.items, config: scorerConfig)
        let candidateItems = scoredItems.map(\.item)
        let relevanceHints = Dictionary(uniqueKeysWithValues: scoredItems.map { ($0.item.id, $0.score) })

        let observationPrompt = ObservationManager.promptString(from: observations, forOccasion: selectedOccasionTier)

        // Collect existing outfit item-ID sets for dedup
        let existingItemSets = existingOutfits.map { outfit in
            outfit.items.map { $0.id.uuidString }.sorted()
        }

        // Fetch outfit-scoped tags for AI auto-tagging
        let allTags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        let outfitTags = allTags.filter { $0.scope == .outfit }
        let tagNames = outfitTags.map(\.name)

        Task {
            do {
                let suggestions = try await AnthropicService.generateOutfits(
                    from: candidateItems,
                    occasion: selectedOccasion,
                    season: selectedSeason,
                    weatherContext: weatherViewModel?.weatherContextString,
                    comfortPreferences: StyleContextHelper.comfortPreferencesString(from: userProfile),
                    styleSummary: styleSummaryText,
                    filterContext: filterContext,
                    existingOutfitItemSets: existingItemSets,
                    availableTagNames: tagNames,
                    observationContext: observationPrompt,
                    itemRelevanceHints: relevanceHints,
                    styleMode: userProfile?.styleMode
                )

                var created: [Outfit] = []
                for suggestion in suggestions {
                    let matchedItems = candidateItems.filter {
                        suggestion.itemIDs.contains($0.id.uuidString)
                    }
                    // Require at least 3 matched items, or all suggested if fewer than 3
                    let minRequired = min(3, suggestion.itemIDs.count)
                    guard matchedItems.count >= minRequired else { continue }

                    let resolvedTags = TagManager.resolveTags(from: suggestion.tags, allTags: allTags, scope: .outfit)
                    let outfit = Outfit(
                        name: suggestion.name,
                        occasion: suggestion.occasion,
                        reasoning: suggestion.reasoning,
                        isAIGenerated: true,
                        items: matchedItems,
                        tags: resolvedTags
                    )

                    // Merge client-side + AI wardrobe gap notes
                    let mergedGaps = OccasionFilter.mergeGaps(clientSide: filterResult.wardrobeGaps, aiSide: suggestion.wardrobeGaps)
                    outfit.wardrobeGaps = Outfit.encodeGaps(mergedGaps)

                    captureWeatherSnapshot(on: outfit)
                    modelContext.insert(outfit)
                    created.append(outfit)
                }

                if created.isEmpty && !suggestions.isEmpty {
                    self.errorMessage = "AI suggested items that couldn't be matched to your wardrobe. Try again."
                    self.isGenerating = false
                    return
                }

                try? modelContext.save()
                self.notifyStyleAnalysis()
                self.generatedOutfits = created
                self.showGeneratedResults = !created.isEmpty
                self.isShowingGenerateSheet = false
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isGenerating = false
        }
    }

    func resetGenerationContext() {
        selectedOccasionTier = nil
        selectedSeason = nil
        errorMessage = nil
    }

    func autoPopulateSeason() {
        guard selectedSeason == nil else { return }
        selectedSeason = weatherViewModel?.suggestedSeason
    }

    // MARK: - Bulk Selection

    func enterSelectionMode(with outfit: Outfit) {
        isSelecting = true
        selectedOutfitIDs = [outfit.persistentModelID]
    }

    func toggleOutfitSelection(_ outfit: Outfit) {
        if selectedOutfitIDs.contains(outfit.persistentModelID) {
            selectedOutfitIDs.remove(outfit.persistentModelID)
        } else {
            selectedOutfitIDs.insert(outfit.persistentModelID)
        }
    }

    func applyTagToSelected(tag: Tag, outfits: [Outfit]) {
        let targets = outfits.filter { selectedOutfitIDs.contains($0.persistentModelID) }
        for outfit in targets {
            if !outfit.tags.contains(where: { $0.persistentModelID == tag.persistentModelID }) {
                outfit.tags.append(tag)
            }
        }
        try? modelContext?.save()
    }

    func removeTagFromSelected(tag: Tag, outfits: [Outfit]) {
        let targets = outfits.filter { selectedOutfitIDs.contains($0.persistentModelID) }
        for outfit in targets {
            outfit.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        }
        try? modelContext?.save()
    }

    func deleteSelectedOutfits(outfits: [Outfit]) {
        guard let modelContext else { return }
        let targets = outfits.filter { selectedOutfitIDs.contains($0.persistentModelID) }
        for outfit in targets {
            modelContext.delete(outfit)
        }
        try? modelContext.save()
        exitSelectionMode()
    }

    func applyBulkTagEdits(edits: [PersistentIdentifier: Bool], outfits: [Outfit], allTags: [Tag]) {
        let targets = outfits.filter { selectedOutfitIDs.contains($0.persistentModelID) }
        for (tagID, shouldHave) in edits {
            guard let tag = allTags.first(where: { $0.persistentModelID == tagID }) else { continue }
            for outfit in targets {
                let has = outfit.tags.contains { $0.persistentModelID == tagID }
                if shouldHave && !has {
                    outfit.tags.append(tag)
                } else if !shouldHave && has {
                    outfit.tags.removeAll { $0.persistentModelID == tagID }
                }
            }
        }
        try? modelContext?.save()
        exitSelectionMode()
    }

    func exitSelectionMode() {
        isSelecting = false
        selectedOutfitIDs = []
    }

    // MARK: - Tag CRUD (delegates to TagManager)

    func createTag(name: String, scope: TagScope = .outfit, context: ModelContext) {
        TagManager.createTag(name: name, scope: scope, context: context)
    }

    func renameTag(_ tag: Tag, to newName: String, context: ModelContext) {
        TagManager.renameTag(tag, to: newName, context: context)
    }

    func deleteTag(_ tag: Tag, context: ModelContext) {
        TagManager.deleteTag(tag, context: context)
    }

    func updateTagColor(_ tag: Tag, hex: String?, context: ModelContext) {
        TagManager.updateTagColor(tag, hex: hex, context: context)
    }

    // MARK: - Weather Snapshot

    private func captureWeatherSnapshot(on outfit: Outfit) {
        if let snapshot = weatherViewModel?.snapshot {
            outfit.weatherTempAtCreation = snapshot.current.temperature
            outfit.weatherFeelsLikeAtCreation = snapshot.current.feelsLike
            outfit.seasonAtCreation = weatherViewModel?.suggestedSeason
        }
        outfit.monthAtCreation = Calendar.current.component(.month, from: Date())
    }

    // MARK: - Style Analysis Trigger

    private func notifyStyleAnalysis() {
        guard let context = modelContext else { return }
        let items = (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? []
        let outfits = (try? context.fetch(FetchDescriptor<Outfit>())) ?? []
        styleViewModel?.analyzeStyle(items: items, outfits: outfits, profile: userProfile)
    }

    // MARK: - Style Context

    func updateStyleContext(from summary: StyleSummary?) {
        styleSummaryText = StyleContextHelper.styleContextString(from: summary)
    }
}
