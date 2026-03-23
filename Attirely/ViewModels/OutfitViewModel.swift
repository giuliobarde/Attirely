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
    var selectedOccasion: String?
    var selectedSeason: String?

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

        // Collect existing outfit item-ID sets for dedup
        let existingOutfits = (try? modelContext.fetch(FetchDescriptor<Outfit>())) ?? []
        let existingItemSets = existingOutfits.map { outfit in
            outfit.items.map { $0.id.uuidString }.sorted()
        }

        // Fetch all tags for AI auto-tagging
        let allTags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        let tagNames = allTags.map(\.name)

        Task {
            do {
                let suggestions = try await AnthropicService.generateOutfits(
                    from: allItems,
                    occasion: selectedOccasion,
                    season: selectedSeason,
                    weatherContext: weatherViewModel?.weatherContextString,
                    comfortPreferences: comfortPreferencesString(from: userProfile),
                    styleSummary: styleSummaryText,
                    existingOutfitItemSets: existingItemSets,
                    availableTagNames: tagNames
                )

                var created: [Outfit] = []
                for suggestion in suggestions {
                    let matchedItems = allItems.filter {
                        suggestion.itemIDs.contains($0.id.uuidString)
                    }
                    // Require at least 3 matched items, or all suggested if fewer than 3
                    let minRequired = min(3, suggestion.itemIDs.count)
                    guard matchedItems.count >= minRequired else { continue }

                    let resolvedTags = resolveTags(from: suggestion.tags, allTags: allTags)
                    let outfit = Outfit(
                        name: suggestion.name,
                        occasion: suggestion.occasion,
                        reasoning: suggestion.reasoning,
                        isAIGenerated: true,
                        items: matchedItems,
                        tags: resolvedTags
                    )
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
        selectedOccasion = nil
        selectedSeason = nil
        errorMessage = nil
    }

    func autoPopulateSeason() {
        guard selectedSeason == nil else { return }
        selectedSeason = weatherViewModel?.suggestedSeason
    }

    // MARK: - Tag Resolution

    private func resolveTags(from names: [String], allTags: [Tag]) -> [Tag] {
        let tagIndex = Dictionary(uniqueKeysWithValues: allTags.map { ($0.name, $0) })
        return names.compactMap { tagIndex[Tag.normalized($0)] }
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

    // MARK: - Tag CRUD

    func createTag(name: String, context: ModelContext) {
        let normalized = Tag.normalized(name)
        guard !normalized.isEmpty else { return }
        let predicate = #Predicate<Tag> { $0.name == normalized }
        let existing = (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
        guard existing == 0 else { return }
        let tag = Tag(name: normalized, isPredefined: false)
        context.insert(tag)
        try? context.save()
    }

    func renameTag(_ tag: Tag, to newName: String, context: ModelContext) {
        guard !tag.isPredefined else { return }
        let normalized = Tag.normalized(newName)
        guard !normalized.isEmpty else { return }
        let predicate = #Predicate<Tag> { $0.name == normalized }
        let existing = (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
        guard existing == 0 else { return }
        tag.name = normalized
        try? context.save()
    }

    func deleteTag(_ tag: Tag, context: ModelContext) {
        guard !tag.isPredefined else { return }
        context.delete(tag)
        try? context.save()
    }

    func updateTagColor(_ tag: Tag, hex: String?, context: ModelContext) {
        tag.colorHex = hex
        try? context.save()
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
        guard let summary, summary.isAIEnriched else {
            styleSummaryText = summary?.overallIdentity
            return
        }
        var ctx = "Overall: \(summary.overallIdentity)"
        for mode in summary.styleModesDecoded {
            ctx += "\n- \(mode.name) (\(mode.formality)): \(mode.description). Colors: \(mode.colorPalette.joined(separator: ", "))"
        }
        if let weather = summary.weatherBehavior {
            ctx += "\nWeather behavior: \(weather)"
        }
        styleSummaryText = ctx
    }

    // MARK: - Comfort Preferences

    func comfortPreferencesString(from profile: UserProfile?) -> String? {
        guard let profile else { return nil }
        var lines: [String] = []

        if let cold = profile.coldSensitivityEnum {
            lines.append("Cold sensitivity: \(cold.rawValue)")
        }
        if let heat = profile.heatSensitivityEnum {
            lines.append("Heat sensitivity: \(heat.rawValue)")
        }
        if let notes = profile.bodyTempNotes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Body temp notes: \(notes.trimmingCharacters(in: .whitespaces))")
        }
        if let layering = profile.layeringPreferenceEnum {
            lines.append("Layering preference: \(layering.rawValue)")
        }
        if let comfort = profile.comfortVsAppearanceEnum {
            lines.append("Comfort vs appearance: \(comfort.rawValue)")
        }
        if let approach = profile.weatherDressingApproachEnum {
            lines.append("Weather dressing: \(approach.rawValue)")
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
