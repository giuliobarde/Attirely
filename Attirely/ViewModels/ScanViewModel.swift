import SwiftUI
import SwiftData

enum ScanProgress: Equatable {
    case idle
    case analyzing
    case checkingDuplicates
    case complete
    case error(String)
}

@Observable
class ScanViewModel {
    var scanProgress: ScanProgress = .idle
    var scannedItems: [ClothingItemDTO] = []
    var selectedImages: [UIImage] = []
    var showingCamera = false
    var showingResults = false
    var savedItemIDs: Set<UUID> = []
    var dismissedItemIDs: Set<UUID> = []
    var duplicateResults: [UUID: [DuplicateResult]] = [:]

    // Outfit detection
    var outfitSuggestion: ScanOutfitSuggestionDTO?
    var outfitSaved = false

    // "Use Existing" duplicate linking
    var existingItemMapping: [UUID: ClothingItem] = [:]
    private var addedImagePaths: [UUID: String] = [:]  // dtoID → path appended to existing item

    var modelContext: ModelContext?
    var styleViewModel: StyleViewModel?

    private var analysisTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var visibleItems: [ClothingItemDTO] {
        scannedItems.filter { !dismissedItemIDs.contains($0.id) }
    }

    var hasUnsavedItems: Bool {
        visibleItems.contains { !savedItemIDs.contains($0.id) && existingItemMapping[$0.id] == nil }
    }

    var isLoading: Bool {
        switch scanProgress {
        case .analyzing: return true
        default: return false
        }
    }

    var errorMessage: String? {
        if case .error(let msg) = scanProgress { return msg }
        return nil
    }

    var isCheckingDuplicates: Bool {
        if case .checkingDuplicates = scanProgress { return true }
        return false
    }

    // MARK: - Outfit Detection Computed Properties

    var outfitCompleteness: OutfitCompletenessValidator.Result {
        let categories = visibleItems.map { dto in
            if let existing = existingItemMapping[dto.id] {
                return existing.category
            }
            return dto.category
        }
        return OutfitCompletenessValidator.validate(categories: categories)
    }

    var isOutfitSaveEnabled: Bool {
        outfitSuggestion != nil && outfitCompleteness != .invalid
    }

    var canSaveOutfit: Bool {
        isOutfitSaveEnabled
    }

    // MARK: - Analysis

    func analyzeImages(_ images: [UIImage]) {
        analysisTask?.cancel()
        selectedImages = images
        showingResults = true
        scanProgress = .analyzing
        scannedItems = []
        savedItemIDs = []
        dismissedItemIDs = []
        duplicateResults = [:]
        outfitSuggestion = nil
        outfitSaved = false
        existingItemMapping = [:]
        addedImagePaths = [:]

        analysisTask = Task {
            do {
                let allTags = (try? modelContext?.fetch(FetchDescriptor<Tag>())) ?? []
                let itemTagNames = allTags.filter { $0.scope == .item }.map(\.name)

                if Task.isCancelled { return }

                let items: [ClothingItemDTO]
                if images.count == 1 {
                    let response = try await AnthropicService.analyzeClothingWithOutfitDetection(
                        image: images[0],
                        availableItemTagNames: itemTagNames
                    )
                    items = response.items
                    self.outfitSuggestion = response.outfit
                } else {
                    items = try await AnthropicService.analyzeClothingMultiImage(
                        images: images,
                        availableItemTagNames: itemTagNames
                    )
                }

                if Task.isCancelled { return }

                if items.isEmpty {
                    self.scanProgress = .error("No clothing items detected. Try a clearer photo.")
                } else {
                    self.scannedItems = items
                    self.scanProgress = .checkingDuplicates
                    await self.checkForDuplicates(items: items)
                    if !Task.isCancelled {
                        self.scanProgress = .complete
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.scanProgress = .error(error.localizedDescription)
                }
            }
        }
    }

    func analyzeImage(_ image: UIImage) {
        analyzeImages([image])
    }

    // MARK: - Item Actions

    func saveItem(_ dto: ClothingItemDTO) {
        guard let modelContext else { return }
        guard existingItemMapping[dto.id] == nil else { return }
        let sourceImage = bestSourceImage(for: dto)

        do {
            let scanImagePath: String?
            if let sourceImage {
                scanImagePath = try ImageStorageService.saveScanImage(sourceImage, id: dto.id)
            } else {
                scanImagePath = nil
            }
            let clothingItem = ClothingItem(from: dto, sourceImagePath: scanImagePath)

            if !dto.tags.isEmpty {
                let allTags = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
                clothingItem.tags = TagManager.resolveTags(from: dto.tags, allTags: allTags, scope: .item)
            }

            modelContext.insert(clothingItem)
            try modelContext.save()
            savedItemIDs.insert(dto.id)
            notifyStyleAnalysisIfNeeded()
        } catch {
            scanProgress = .error("Failed to save item: \(error.localizedDescription)")
        }
    }

    func saveAllItems() {
        for item in visibleItems where !savedItemIDs.contains(item.id) && existingItemMapping[item.id] == nil {
            saveItem(item)
        }
    }

    func dismissItem(_ dto: ClothingItemDTO) {
        dismissedItemIDs.insert(dto.id)
    }

    func updateScannedItem(_ dto: ClothingItemDTO) {
        if let index = scannedItems.firstIndex(where: { $0.id == dto.id }) {
            scannedItems[index] = dto
        }
    }

    func isItemSaved(_ dto: ClothingItemDTO) -> Bool {
        savedItemIDs.contains(dto.id)
    }

    func isItemLinked(_ dto: ClothingItemDTO) -> Bool {
        existingItemMapping[dto.id] != nil
    }

    func retry() {
        guard !selectedImages.isEmpty else { return }
        analyzeImages(selectedImages)
    }

    // MARK: - "Use Existing" Actions

    func useExistingItem(dtoID: UUID, existingItem: ClothingItem) {
        existingItemMapping[dtoID] = existingItem   // synchronous so UI reacts immediately

        Task {
            // Guard: if user undid the link before the Task ran, skip everything
            guard existingItemMapping[dtoID] != nil else { return }
            guard let image = bestSourceImage(for: dtoID) else { return }
            guard let modelContext else { return }

            do {
                let path = try ImageStorageService.saveScanImage(image, id: UUID())
                existingItem.appendAdditionalImagePath(path)
                existingItem.updatedAt = Date()
                try modelContext.save()
                addedImagePaths[dtoID] = path
            } catch {
                // Non-fatal — linking still works, image just won't be persisted
            }
        }
    }

    func revertToNewItem(dtoID: UUID) {
        if let existing = existingItemMapping[dtoID],
           let path = addedImagePaths[dtoID] {
            var paths = existing.additionalImagePathsDecoded
            paths.removeAll { $0 == path }
            existing.additionalImagePathsDecoded = paths
            existing.updatedAt = Date()
            try? modelContext?.save()
            ImageStorageService.deleteImage(relativePath: path)
            addedImagePaths.removeValue(forKey: dtoID)
        }
        existingItemMapping.removeValue(forKey: dtoID)
    }

    // MARK: - Outfit Actions

    func saveOutfit(name: String, occasion: String) {
        guard let modelContext else { return }

        // Auto-save any unsaved new items first
        for dto in visibleItems where !savedItemIDs.contains(dto.id) && existingItemMapping[dto.id] == nil {
            saveItem(dto)
        }

        var outfitItems: [ClothingItem] = []
        for dto in visibleItems {
            if let existing = existingItemMapping[dto.id] {
                outfitItems.append(existing)
            } else if savedItemIDs.contains(dto.id) {
                let dtoID = dto.id
                let predicate = #Predicate<ClothingItem> { $0.id == dtoID }
                let descriptor = FetchDescriptor<ClothingItem>(predicate: predicate)
                if let item = try? modelContext.fetch(descriptor).first {
                    outfitItems.append(item)
                }
            }
        }

        guard outfitItems.count >= 2 else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOccasion = occasion.trimmingCharacters(in: .whitespacesAndNewlines)

        let outfit = Outfit(
            name: trimmedName.isEmpty ? nil : trimmedName,
            occasion: trimmedOccasion.isEmpty ? nil : trimmedOccasion,
            reasoning: outfitSuggestion?.reasoning,
            isAIGenerated: true,
            items: outfitItems
        )

        modelContext.insert(outfit)
        do {
            try modelContext.save()
            outfitSaved = true
        } catch {
            scanProgress = .error("Failed to save outfit: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    func bestSourceImage(for dto: ClothingItemDTO) -> UIImage? {
        guard !selectedImages.isEmpty else { return nil }
        let index = dto.sourceImageIndices.first ?? 0
        guard index < selectedImages.count else { return selectedImages.first }
        return selectedImages[index]
    }

    func bestSourceImage(for dtoID: UUID) -> UIImage? {
        guard let dto = scannedItems.first(where: { $0.id == dtoID }) else { return nil }
        return bestSourceImage(for: dto)
    }

    private func checkForDuplicates(items: [ClothingItemDTO]) async {
        guard let modelContext else { return }

        for dto in items {
            if Task.isCancelled { return }

            guard let image = bestSourceImage(for: dto) else { continue }

            let category = dto.category
            let color = dto.primaryColor
            let predicate = #Predicate<ClothingItem> {
                $0.category == category && $0.primaryColor == color
            }
            let descriptor = FetchDescriptor<ClothingItem>(predicate: predicate)

            guard let candidates = try? modelContext.fetch(descriptor),
                  !candidates.isEmpty else { continue }

            if let results = try? await AnthropicService.checkDuplicates(
                scannedItem: dto, candidates: candidates, image: image
            ) {
                let matches = results.filter { $0.classification != .noMatch }
                if !matches.isEmpty {
                    duplicateResults[dto.id] = matches
                }
            }
        }
    }

    private func notifyStyleAnalysisIfNeeded() {
        guard let context = modelContext else { return }
        let items = (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? []
        let outfits = (try? context.fetch(FetchDescriptor<Outfit>())) ?? []
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        styleViewModel?.analyzeStyle(items: items, outfits: outfits, profile: profile)
    }
}
