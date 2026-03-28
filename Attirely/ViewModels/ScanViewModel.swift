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

    var modelContext: ModelContext?
    var styleViewModel: StyleViewModel?

    private var analysisTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var visibleItems: [ClothingItemDTO] {
        scannedItems.filter { !dismissedItemIDs.contains($0.id) }
    }

    var hasUnsavedItems: Bool {
        visibleItems.contains { !savedItemIDs.contains($0.id) }
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

        analysisTask = Task {
            do {
                let allTags = (try? modelContext?.fetch(FetchDescriptor<Tag>())) ?? []
                let itemTagNames = allTags.filter { $0.scope == .item }.map(\.name)

                if Task.isCancelled { return }

                let items: [ClothingItemDTO]
                if images.count == 1 {
                    items = try await AnthropicService.analyzeClothing(
                        image: images[0],
                        availableItemTagNames: itemTagNames
                    )
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
        for item in visibleItems where !savedItemIDs.contains(item.id) {
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

    func retry() {
        guard !selectedImages.isEmpty else { return }
        analyzeImages(selectedImages)
    }

    // MARK: - Helpers

    func bestSourceImage(for dto: ClothingItemDTO) -> UIImage? {
        guard !selectedImages.isEmpty else { return nil }
        let index = dto.sourceImageIndices.first ?? 0
        guard index < selectedImages.count else { return selectedImages.first }
        return selectedImages[index]
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
