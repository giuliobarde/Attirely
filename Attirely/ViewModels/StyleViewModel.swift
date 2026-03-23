import SwiftUI
import SwiftData

@Observable
class StyleViewModel {
    var isAnalyzing = false
    var errorMessage: String?
    var modelContext: ModelContext?

    private var lastAnalysisRequestTime: Date?
    private static let debounceInterval: TimeInterval = 30

    var canAnalyze: Bool {
        guard let context = modelContext else { return false }
        let count = (try? context.fetchCount(FetchDescriptor<ClothingItem>())) ?? 0
        return count >= 8
    }

    // MARK: - Threshold Check

    func shouldAutoAnalyze(
        itemCount: Int,
        favoritedOutfitCount: Int,
        summary: StyleSummary?
    ) -> Bool {
        guard itemCount >= 8 else { return false }

        if let last = lastAnalysisRequestTime,
           Date().timeIntervalSince(last) < Self.debounceInterval {
            return false
        }

        guard let summary else {
            return true
        }

        let itemDelta = itemCount - summary.itemCountAtLastAnalysis
        let favDelta = favoritedOutfitCount - summary.favoritedOutfitCountAtLastAnalysis

        return itemDelta >= 4 || favDelta >= 2
    }

    // MARK: - Run Analysis

    func analyzeStyle(
        items: [ClothingItem],
        outfits: [Outfit],
        profile: UserProfile?,
        force: Bool = false
    ) {
        guard let context = modelContext else { return }
        guard !isAnalyzing else { return }

        let descriptor = FetchDescriptor<StyleSummary>()
        let existingSummary = (try? context.fetch(descriptor))?.first

        if !force {
            let favCount = outfits.filter { $0.isFavorite }.count
            guard shouldAutoAnalyze(
                itemCount: items.count,
                favoritedOutfitCount: favCount,
                summary: existingSummary
            ) else { return }
        }

        isAnalyzing = true
        errorMessage = nil
        lastAnalysisRequestTime = Date()

        Task {
            do {
                let analysis = try await AnthropicService.analyzeStyle(
                    items: items,
                    outfits: outfits,
                    profile: profile,
                    existingSummary: existingSummary
                )

                let favCount = outfits.filter { $0.isFavorite }.count

                if let existing = existingSummary {
                    existing.overallIdentity = analysis.overallIdentity
                    existing.styleModesDecoded = analysis.styleModes
                    existing.temporalNotes = analysis.temporalNotes
                    existing.gapObservations = analysis.gapObservations
                    existing.weatherBehavior = analysis.weatherBehavior
                    existing.lastAnalyzedAt = Date()
                    existing.itemCountAtLastAnalysis = items.count
                    existing.outfitCountAtLastAnalysis = outfits.count
                    existing.favoritedOutfitCountAtLastAnalysis = favCount
                    existing.analysisVersion += 1
                    existing.isAIEnriched = true
                } else {
                    let summary = StyleSummary(
                        overallIdentity: analysis.overallIdentity,
                        itemCountAtLastAnalysis: items.count,
                        outfitCountAtLastAnalysis: outfits.count,
                        favoritedOutfitCountAtLastAnalysis: favCount
                    )
                    summary.styleModesDecoded = analysis.styleModes
                    summary.temporalNotes = analysis.temporalNotes
                    summary.gapObservations = analysis.gapObservations
                    summary.weatherBehavior = analysis.weatherBehavior
                    summary.isAIEnriched = true
                    context.insert(summary)
                }

                try? context.save()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isAnalyzing = false
        }
    }

    // MARK: - Agent Insight

    func appendAgentInsight(_ insight: String) {
        guard let context = modelContext,
              let summary = (try? context.fetch(FetchDescriptor<StyleSummary>()))?.first
        else { return }

        let existing = summary.gapObservations ?? ""
        let separator = existing.isEmpty ? "" : "\n"
        summary.gapObservations = existing + separator + "User preference: " + insight
        try? context.save()
    }
}
