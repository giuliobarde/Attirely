import SwiftUI
import SwiftData

@Observable
class OutfitViewModel {
    // List filtering
    var showFavoritesOnly = false

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

    var modelContext: ModelContext?

    // MARK: - List

    func filteredOutfits(from outfits: [Outfit]) -> [Outfit] {
        if showFavoritesOnly {
            return outfits.filter { $0.isFavorite }
        }
        return outfits
    }

    // MARK: - Favorites

    func toggleFavorite(_ outfit: Outfit) {
        outfit.isFavorite.toggle()
        try? modelContext?.save()
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
        modelContext.insert(outfit)
        try? modelContext.save()

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

        Task {
            do {
                let suggestions = try await AnthropicService.generateOutfits(
                    from: allItems,
                    occasion: selectedOccasion,
                    season: selectedSeason
                )

                var created: [Outfit] = []
                for suggestion in suggestions {
                    let matchedItems = allItems.filter {
                        suggestion.itemIDs.contains($0.id.uuidString)
                    }
                    guard !matchedItems.isEmpty else { continue }

                    let outfit = Outfit(
                        name: suggestion.name,
                        occasion: suggestion.occasion,
                        reasoning: suggestion.reasoning,
                        isAIGenerated: true,
                        items: matchedItems
                    )
                    modelContext.insert(outfit)
                    created.append(outfit)
                }

                try? modelContext.save()
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
}
