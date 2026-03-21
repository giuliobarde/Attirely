import SwiftUI
import SwiftData

@Observable
class ScanViewModel {
    var isLoading = false
    var scannedItems: [ClothingItemDTO] = []
    var errorMessage: String?
    var selectedImage: UIImage?
    var showingCamera = false
    var showingResults = false
    var savedItemIDs: Set<UUID> = []
    var dismissedItemIDs: Set<UUID> = []
    var duplicateResults: [UUID: [DuplicateResult]] = [:]
    var isCheckingDuplicates = false

    var modelContext: ModelContext?

    var visibleItems: [ClothingItemDTO] {
        scannedItems.filter { !dismissedItemIDs.contains($0.id) }
    }

    var hasUnsavedItems: Bool {
        visibleItems.contains { !savedItemIDs.contains($0.id) }
    }

    func analyzeImage(_ image: UIImage) {
        selectedImage = image
        showingResults = true
        isLoading = true
        errorMessage = nil
        scannedItems = []
        savedItemIDs = []
        dismissedItemIDs = []
        duplicateResults = [:]

        Task {
            do {
                let items = try await AnthropicService.analyzeClothing(image: image)
                if items.isEmpty {
                    self.errorMessage = "No clothing items detected. Try a clearer photo."
                } else {
                    self.scannedItems = items
                    await self.checkForDuplicates(items: items, image: image)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func saveItem(_ dto: ClothingItemDTO) {
        guard let modelContext, let selectedImage else { return }
        do {
            let scanImagePath = try ImageStorageService.saveScanImage(selectedImage, id: dto.id)
            let clothingItem = ClothingItem(from: dto, sourceImagePath: scanImagePath)
            modelContext.insert(clothingItem)
            try modelContext.save()
            savedItemIDs.insert(dto.id)
        } catch {
            errorMessage = "Failed to save item: \(error.localizedDescription)"
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

    func isItemSaved(_ dto: ClothingItemDTO) -> Bool {
        savedItemIDs.contains(dto.id)
    }

    func retry() {
        guard let image = selectedImage else { return }
        analyzeImage(image)
    }

    private func checkForDuplicates(items: [ClothingItemDTO], image: UIImage) async {
        guard let modelContext else { return }
        isCheckingDuplicates = true

        for dto in items {
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

        isCheckingDuplicates = false
    }
}
