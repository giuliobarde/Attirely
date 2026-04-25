import Foundation
import SwiftData

// State the executor needs from the view model. Exposed as a protocol so the executor
// doesn't retain the VM directly and so its responsibilities stay explicit.
@MainActor
protocol AgentToolHost: AnyObject {
    var wardrobeItems: [ClothingItem] { get }
    var allOutfits: [Outfit] { get }
    var messages: [ChatMessage] { get }
    var styleSummary: StyleSummary? { get }
    var styleSummaryText: String? { get }
    var userProfile: UserProfile? { get }
    var weatherViewModel: WeatherViewModel? { get }
    var modelContext: ModelContext? { get }

    var pendingOutfitItems: [UUID: [ClothingItem]] { get set }
    var pendingOutfitTags: [UUID: [Tag]] { get set }
    var sourceOutfitIDForCopy: [UUID: UUID] { get set }
    var conversationGeneratedItemSets: [[String]] { get set }
    var pendingInsights: [(insight: String, confidence: String)] { get set }

    func refreshMessageContaining(outfitID: UUID)
    func replaceOutfit(fromMessageContaining copyID: UUID, removing: UUID)
    func saveIfPossible()
    func notifyStyleAnalysis()
}

// Executes the six agent tools. All mutations go through the host so the VM remains
// the sole observable and can enforce save/notify invariants.
@MainActor
final class AgentToolExecutor {

    private weak var host: AgentToolHost?

    init(host: AgentToolHost) {
        self.host = host
    }

    // MARK: - Router

    func execute(_ call: ToolUseBlock) async -> (String, [Outfit], [ClothingItem], String?) {
        AgentTelemetry.recordToolCall(call.name.rawValue)
        switch call.name {
        case .generateOutfit:
            return await executeGenerateOutfit(GenerateOutfitInput(from: call.inputJSON))
        case .searchOutfits:
            return executeSearchOutfits(SearchOutfitsInput(from: call.inputJSON))
        case .searchWardrobe:
            return executeSearchWardrobe(SearchWardrobeInput(from: call.inputJSON))
        case .updateStyleInsight:
            return executeUpdateStyleInsight(UpdateStyleInsightInput(from: call.inputJSON))
        case .editOutfit:
            return executeEditOutfit(EditOutfitInput(from: call.inputJSON))
        case .suggestPurchases:
            return ("suggestPurchases is handled separately.", [], [], nil)
        case .askUserQuestion:
            return ("askUserQuestion is handled separately.", [], [], nil)
        }
    }

    // MARK: - generateOutfit

    func executeGenerateOutfit(_ input: GenerateOutfitInput) async -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        let wardrobe = host.wardrobeItems
        guard wardrobe.count >= 2 else {
            return ("The user's wardrobe has fewer than 2 items. They need to add more items before generating outfits.", [], [], nil)
        }

        do {
            _ = try ConfigManager.apiKey() // surfaces missing-key error before the API call

            // Prefer ID-addressed inputs; fall back to description matching for anything
            // the agent cited without an alias. Union the two so callers can mix both.
            let (idMatched, unknownAliases) = resolveItemIDs(input.mustIncludeItemIDs, in: wardrobe)
            let descMatched = input.mustIncludeItems.compactMap { desc -> ClothingItem? in
                AgentTelemetry.recordFuzzyFallback(AgentToolName.generateOutfit.rawValue)
                return OutfitMatcher.matchItem(description: desc, in: wardrobe)
            }
            let mustIncludeResolved = unique(idMatched + descMatched)

            let tier = input.occasion.flatMap { OccasionTier(fromString: $0) }
            let filterResult = OccasionFilter.filterItems(wardrobe, for: tier)
            let filterContext = OccasionFilter.buildFilterContext(from: filterResult)

            var filteredItems = filterResult.items
            for item in mustIncludeResolved where !filteredItems.contains(where: { $0.id == item.id }) {
                filteredItems.append(item)
            }

            let observations = host.styleSummary?.activeObservations ?? []
            let scorerConfig = RelevanceScorerConfig(
                occasion: tier,
                season: host.weatherViewModel?.suggestedSeason,
                currentTemp: host.weatherViewModel?.snapshot?.current.temperature,
                observations: observations,
                allOutfits: host.allOutfits
            )
            let scoredItems = RelevanceScorer.selectCandidates(from: filteredItems, config: scorerConfig)
            var candidateItems = scoredItems.map(\.item)
            let relevanceHints = Dictionary(uniqueKeysWithValues: scoredItems.map { ($0.item.id, $0.score) })

            for item in mustIncludeResolved where !candidateItems.contains(where: { $0.id == item.id }) {
                candidateItems.append(item)
            }

            let observationPrompt = ObservationManager.promptString(from: observations, forOccasion: tier)

            let savedOutfitItemSets = host.allOutfits.map { outfit in
                outfit.items.map { $0.id.uuidString }.sorted()
            }
            let existingItemSets = savedOutfitItemSets + host.conversationGeneratedItemSets

            let allTags = (try? host.modelContext?.fetch(FetchDescriptor<Tag>())) ?? []
            let outfitTags = allTags.filter { $0.scope == .outfit }
            let tagNames = outfitTags.map(\.name)

            let mustIncludeIDStrings = Set(mustIncludeResolved.map(\.id.uuidString))

            let suggestions = try await AnthropicService.generateOutfits(
                from: candidateItems,
                occasion: input.occasion,
                season: host.weatherViewModel?.suggestedSeason,
                weatherContext: host.weatherViewModel?.weatherContextString,
                comfortPreferences: StyleContextHelper.comfortPreferencesString(from: host.userProfile),
                styleSummary: host.styleSummaryText,
                filterContext: filterContext,
                existingOutfitItemSets: existingItemSets,
                availableTagNames: tagNames,
                observationContext: observationPrompt,
                itemRelevanceHints: relevanceHints,
                mustIncludeItemIDs: mustIncludeIDStrings,
                styleMode: host.userProfile?.styleMode,
                styleDirection: host.userProfile?.styleDirection
            )

            var createdOutfits: [Outfit] = []
            for suggestion in suggestions {
                var matchedItems = candidateItems.filter {
                    suggestion.itemIDs.contains($0.id.uuidString)
                }

                for item in mustIncludeResolved where !matchedItems.contains(where: { $0.id == item.id }) {
                    matchedItems.append(item)
                }

                let minRequired = min(3, suggestion.itemIDs.count)
                guard matchedItems.count >= minRequired else { continue }

                let resolvedTags = TagManager.resolveTags(from: suggestion.tags, allTags: allTags, scope: .outfit)
                let outfit = Outfit(
                    name: suggestion.name,
                    occasion: suggestion.occasion,
                    reasoning: suggestion.reasoning,
                    isAIGenerated: true,
                    items: [],
                    tags: []
                )
                host.pendingOutfitItems[outfit.id] = matchedItems
                host.pendingOutfitTags[outfit.id] = resolvedTags

                let generatedItemIDs = matchedItems.map { $0.id.uuidString }.sorted()
                host.conversationGeneratedItemSets.append(generatedItemIDs)

                let mergedGaps = OccasionFilter.mergeGaps(clientSide: filterResult.wardrobeGaps, aiSide: suggestion.wardrobeGaps)
                outfit.wardrobeGaps = Outfit.encodeGaps(mergedGaps)

                createdOutfits.append(outfit)
            }

            if createdOutfits.isEmpty {
                return ("Could not generate a valid outfit from the wardrobe. Some suggested items could not be matched.", [], [], nil)
            }

            let outfit = createdOutfits[0]
            let matchedItems = host.pendingOutfitItems[outfit.id] ?? []
            let itemSummary = matchedItems
                .map { "\(OutfitMatcher.alias(for: $0)) \($0.type) (\($0.primaryColor))" }
                .joined(separator: ", ")
            var resultText = """
            Generated outfit: \"\(outfit.displayName)\" (outfit id: \(OutfitMatcher.alias(for: outfit)))
            Occasion: \(outfit.occasion ?? "General")
            Items: \(itemSummary)
            Reasoning: \(outfit.reasoning ?? "")
            """
            if !unknownAliases.isEmpty {
                resultText += "\nUnknown aliases ignored: \(unknownAliases.joined(separator: ", ")) — call searchWardrobe to see current IDs."
            }

            return (resultText, createdOutfits, [], nil)
        } catch AnthropicError.allSuggestionsDuplicate {
            let message = AnthropicError.allSuggestionsDuplicate.errorDescription ?? "No new outfit combination available."
            return ("Every suggestion the stylist proposed duplicated an outfit the user already has. Tell the user: \(message)", [], [], nil)
        } catch {
            return ("Failed to generate outfit: \(error.localizedDescription)", [], [], nil)
        }
    }

    // MARK: - searchOutfits

    func executeSearchOutfits(_ input: SearchOutfitsInput) -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        var matches = host.allOutfits

        if !input.tags.isEmpty {
            let normalizedTags = input.tags.map { Tag.normalized($0) }
            matches = matches.filter { outfit in
                normalizedTags.contains { tagName in
                    outfit.tags.contains { $0.name == tagName }
                }
            }
        }

        if let query = input.query, !query.isEmpty {
            let words = query.lowercased().split(separator: " ").map { String($0) }
            matches = matches.filter { outfit in
                let searchableText = [
                    outfit.name ?? "",
                    outfit.occasion ?? "",
                    outfit.reasoning ?? "",
                    outfit.items.map { "\($0.type) \($0.primaryColor) \($0.category)" }.joined(separator: " "),
                    outfit.tags.map(\.name).joined(separator: " ")
                ].joined(separator: " ").lowercased()

                return words.allSatisfy { searchableText.contains($0) }
            }
        }

        matches.sort { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return a.createdAt > b.createdAt
        }

        let top = Array(matches.prefix(5))

        if top.isEmpty {
            return ("No saved outfits found matching this search. I can generate a new outfit for you if you'd like.", [], [], nil)
        }

        var result = "Found \(matches.count) outfit\(matches.count == 1 ? "" : "s"):\n"
        for outfit in top {
            let outfitAlias = OutfitMatcher.alias(for: outfit)
            let items = outfit.items
                .map { "\(OutfitMatcher.alias(for: $0)) \($0.type) (\($0.primaryColor))" }
                .joined(separator: ", ")
            let tags = outfit.tags.map(\.name).joined(separator: ", ")
            result += "- \(outfitAlias) | \"\(outfit.displayName)\" | Items: \(items)"
            if !tags.isEmpty { result += " | Tags: \(tags)" }
            if outfit.isFavorite { result += " ⭐" }
            result += "\n"
        }

        return (result, top, [], nil)
    }

    // MARK: - searchWardrobe

    private static let searchStopWords: Set<String> = [
        "a", "an", "the", "for", "to", "in", "on", "with", "and", "or", "my",
        "any", "some", "that", "this", "those", "these", "of", "is", "are",
        "it", "its", "i", "me", "do", "have", "has", "can", "would", "could",
        "today", "tonight", "tomorrow", "weather", "something", "anything", "items"
    ]

    func executeSearchWardrobe(_ input: SearchWardrobeInput) -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        let query = input.query.lowercased()
        let words = query.split(separator: " ").map { String($0) }
            .filter { !Self.searchStopWords.contains($0) }

        guard !words.isEmpty else {
            return ("No items found matching '\(input.query)'.", [], [], nil)
        }

        let scored = host.wardrobeItems.compactMap { item -> (ClothingItem, Int)? in
            let searchableText = [
                item.type, item.category, item.primaryColor,
                item.secondaryColor ?? "", item.pattern,
                item.fabricEstimate, item.formality,
                item.itemDescription, item.brand ?? "",
                item.season.joined(separator: " ")
            ].joined(separator: " ").lowercased()

            let matchCount = words.filter { searchableText.contains($0) }.count
            return matchCount > 0 ? (item, matchCount) : nil
        }
        .sorted { $0.1 > $1.1 }

        let matches = scored.map(\.0)

        if matches.isEmpty {
            return ("No items found matching '\(input.query)'.", [], [], nil)
        }

        var result = "Found \(matches.count) item\(matches.count == 1 ? "" : "s"):\n"
        for item in matches {
            result += "- \(OutfitMatcher.alias(for: item)) | \(item.type) | \(item.category) | \(item.primaryColor) | \(item.formality) | \(item.itemDescription)\n"
        }

        return (result, [], matches, nil)
    }

    // MARK: - updateStyleInsight

    func executeUpdateStyleInsight(_ input: UpdateStyleInsightInput) -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        host.pendingInsights.append((insight: input.insight, confidence: input.confidence))

        let threshold: Int
        switch input.confidence {
        case "high": threshold = 1
        case "medium": threshold = 2
        default: threshold = 3
        }

        let (category, signal) = ObservationManager.classifyInsight(
            input.insight,
            category: input.category,
            signal: input.signal
        )

        if let summary = host.styleSummary {
            var observations = summary.behavioralNotesDecoded
            observations = ObservationManager.recordObservation(
                pattern: input.insight,
                category: category,
                signal: signal,
                threshold: threshold,
                occasionContext: nil,
                in: observations
            )
            summary.behavioralNotesDecoded = observations
            host.saveIfPossible()
        }

        return ("Insight recorded.", [], [], input.insight)
    }

    // MARK: - editOutfit

    func executeEditOutfit(_ input: EditOutfitInput) -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        guard let outfit = resolveTargetOutfit(input: input, host: host) else {
            let label = input.outfitID ?? input.outfitName ?? "(unspecified)"
            return ("Could not find an outfit matching '\(label)' in this conversation or wardrobe.", [], [], nil)
        }
        if outfit.modelContext != nil {
            return executeEditSavedOutfitAsProposal(input, source: outfit)
        } else {
            return executeEditConversationOutfit(input, outfit: outfit)
        }
    }

    private func resolveTargetOutfit(input: EditOutfitInput, host: AgentToolHost) -> Outfit? {
        if let id = input.outfitID, !id.isEmpty {
            let conversationOutfits = Array(host.messages.flatMap(\.outfits))
            if let match = OutfitMatcher.resolveAlias(id, in: conversationOutfits) {
                return match
            }
            if let match = OutfitMatcher.resolveAlias(id, in: host.allOutfits) {
                return match
            }
            AgentTelemetry.recordUnknownAlias(id, tool: AgentToolName.editOutfit.rawValue)
        }
        if let name = input.outfitName, !name.isEmpty {
            AgentTelemetry.recordFuzzyFallback(AgentToolName.editOutfit.rawValue)
        }
        return OutfitMatcher.resolveOutfit(
            named: input.outfitName ?? "",
            conversationMessages: host.messages,
            pendingOutfitItems: host.pendingOutfitItems,
            savedOutfits: host.allOutfits
        )
    }

    private func executeEditConversationOutfit(
        _ input: EditOutfitInput,
        outfit: Outfit
    ) -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        var currentItems = host.pendingOutfitItems[outfit.id] ?? outfit.items

        let edits = applyItemEdits(
            removeIDs: input.removeItemIDs,
            addIDs: input.addItemIDs,
            removeDescs: input.removeItems,
            addDescs: input.addItems,
            to: currentItems,
            occasionContext: outfit.occasion
        )
        currentItems = edits.items

        if let newName = input.newName, !newName.isEmpty { outfit.name = newName }
        if let newOccasion = input.newOccasion, !newOccasion.isEmpty { outfit.occasion = newOccasion }

        host.pendingOutfitItems[outfit.id] = currentItems

        let warnings = OutfitLayerOrder.warnings(for: currentItems)

        host.refreshMessageContaining(outfitID: outfit.id)

        var summary = "Updated outfit \"\(outfit.displayName)\" (outfit id: \(OutfitMatcher.alias(for: outfit)))."
        if !edits.removed.isEmpty { summary += " Removed: \(edits.removed.joined(separator: ", "))." }
        if !edits.added.isEmpty { summary += " Added: \(edits.added.joined(separator: ", "))." }
        if !edits.unmatchedRemove.isEmpty { summary += " Could not find in outfit: \(edits.unmatchedRemove.joined(separator: ", "))." }
        if !edits.unmatchedAdd.isEmpty { summary += " Could not find in wardrobe: \(edits.unmatchedAdd.joined(separator: ", "))." }
        let itemList = currentItems
            .map { "\(OutfitMatcher.alias(for: $0)) \($0.type) (\($0.primaryColor))" }
            .joined(separator: ", ")
        summary += " Current items (\(currentItems.count)): \(itemList)."
        if !warnings.isEmpty { summary += " Warnings: \(warnings.joined(separator: "; "))." }

        return (summary, [], [], nil)
    }

    private func executeEditSavedOutfitAsProposal(
        _ input: EditOutfitInput,
        source: Outfit
    ) -> (String, [Outfit], [ClothingItem], String?) {
        guard let host else { return ("Internal error: host released.", [], [], nil) }
        let edits = applyItemEdits(
            removeIDs: input.removeItemIDs,
            addIDs: input.addItemIDs,
            removeDescs: input.removeItems,
            addDescs: input.addItems,
            to: source.items,
            occasionContext: source.occasion
        )

        let nameChanged = !(input.newName?.isEmpty ?? true)
        let occasionChanged = !(input.newOccasion?.isEmpty ?? true)

        if edits.removed.isEmpty && edits.added.isEmpty && !nameChanged && !occasionChanged {
            var msg = "No changes were applied to \"\(source.displayName)\"."
            if !edits.unmatchedRemove.isEmpty { msg += " Could not locate \(edits.unmatchedRemove.joined(separator: ", ")) in the outfit." }
            if !edits.unmatchedAdd.isEmpty { msg += " Could not locate \(edits.unmatchedAdd.joined(separator: ", ")) in the wardrobe." }
            msg += " Ask the user to clarify or rephrase."
            return (msg, [], [], nil)
        }

        let copy = Outfit(
            name: nameChanged ? input.newName : source.name,
            occasion: occasionChanged ? input.newOccasion : source.occasion,
            reasoning: source.reasoning,
            isAIGenerated: source.isAIGenerated,
            items: [],
            tags: []
        )

        host.pendingOutfitItems[copy.id] = edits.items
        host.pendingOutfitTags[copy.id] = source.tags
        host.sourceOutfitIDForCopy[copy.id] = source.id

        let warnings = OutfitLayerOrder.warnings(for: edits.items)
        let itemList = edits.items
            .map { "\(OutfitMatcher.alias(for: $0)) \($0.type) (\($0.primaryColor))" }
            .joined(separator: ", ")

        var summary = "Proposed an edit to the saved outfit \"\(source.displayName)\"."
        if !edits.removed.isEmpty { summary += " Removed: \(edits.removed.joined(separator: ", "))." }
        if !edits.added.isEmpty { summary += " Added: \(edits.added.joined(separator: ", "))." }
        if !edits.unmatchedRemove.isEmpty { summary += " Could not find in outfit: \(edits.unmatchedRemove.joined(separator: ", "))." }
        if !edits.unmatchedAdd.isEmpty { summary += " Could not find in wardrobe: \(edits.unmatchedAdd.joined(separator: ", "))." }
        summary += " Proposed items (\(edits.items.count)): \(itemList)."
        if !warnings.isEmpty { summary += " Warnings: \(warnings.joined(separator: "; "))." }

        return (summary, [copy], [], nil)
    }

    func updateOriginalFromCopy(_ copy: Outfit) {
        guard let host,
              let sourceID = host.sourceOutfitIDForCopy[copy.id],
              let source = host.allOutfits.first(where: { $0.id == sourceID }) else { return }

        let copyItems = host.pendingOutfitItems[copy.id] ?? copy.items
        let copyTags = host.pendingOutfitTags[copy.id] ?? copy.tags

        source.items = copyItems
        source.tags = copyTags
        if let newName = copy.name, !newName.isEmpty { source.name = newName }
        if let newOccasion = copy.occasion, !newOccasion.isEmpty { source.occasion = newOccasion }

        host.saveIfPossible()
        host.notifyStyleAnalysis()

        host.pendingOutfitItems.removeValue(forKey: copy.id)
        host.pendingOutfitTags.removeValue(forKey: copy.id)
        host.sourceOutfitIDForCopy.removeValue(forKey: copy.id)

        host.replaceOutfit(fromMessageContaining: copy.id, removing: copy.id)
        host.refreshMessageContaining(outfitID: source.id)
    }

    // MARK: - suggestPurchases

    func executeSuggestPurchases(_ input: SuggestPurchasesInput) async -> (String, [PurchaseSuggestionDTO]) {
        AgentTelemetry.recordToolCall(AgentToolName.suggestPurchases.rawValue)
        guard let host else { return ("Internal error: host released.", []) }
        guard !host.wardrobeItems.isEmpty else {
            return ("The user's wardrobe is empty. Ask them to add some items first before suggesting purchases.", [])
        }

        do {
            let suggestions = try await AnthropicService.suggestPurchases(
                wardrobeItems: host.wardrobeItems,
                category: input.category,
                styleSummary: host.styleSummaryText,
                styleMode: host.userProfile?.styleMode,
                styleDirection: host.userProfile?.styleDirection
            )

            guard !suggestions.isEmpty else {
                return ("No purchase suggestions could be generated.", [])
            }

            var resultText = "Generated \(suggestions.count) purchase suggestion\(suggestions.count == 1 ? "" : "s"):\n"
            for (i, s) in suggestions.enumerated() {
                resultText += "\(i + 1). \(s.description) (\(s.category)) — pairs with \(s.wardrobeCompatibilityCount) items\n"
            }

            return (resultText, suggestions)
        } catch {
            return ("Failed to generate suggestions: \(error.localizedDescription)", [])
        }
    }

    // MARK: - Shared edit helper

    private struct EditResult {
        var items: [ClothingItem]
        var removed: [String]
        var added: [String]
        var unmatchedRemove: [String]
        var unmatchedAdd: [String]
    }

    private func applyItemEdits(
        removeIDs: [String],
        addIDs: [String],
        removeDescs: [String],
        addDescs: [String],
        to startItems: [ClothingItem],
        occasionContext: String?
    ) -> EditResult {
        guard let host else {
            return EditResult(items: startItems, removed: [], added: [], unmatchedRemove: [], unmatchedAdd: [])
        }

        var items = startItems
        var removed: [String] = []
        var added: [String] = []
        var unmatchedRemove: [String] = []
        var unmatchedAdd: [String] = []

        // Phase 1: alias-addressed removals (deterministic)
        for alias in removeIDs {
            if let match = OutfitMatcher.resolveAlias(alias, in: items) {
                items.removeAll { $0.id == match.id }
                removed.append("\(match.type) (\(match.primaryColor))")
                recordNegativeSignal(for: match, occasionContext: occasionContext)
            } else {
                unmatchedRemove.append(alias)
                AgentTelemetry.recordUnknownAlias(alias, tool: AgentToolName.editOutfit.rawValue)
            }
        }

        // Phase 2: description-addressed removals (fallback)
        for desc in removeDescs {
            AgentTelemetry.recordFuzzyFallback(AgentToolName.editOutfit.rawValue)
            if let match = OutfitMatcher.matchItem(description: desc, in: items) {
                items.removeAll { $0.id == match.id }
                removed.append("\(match.type) (\(match.primaryColor))")
                recordNegativeSignal(for: match, occasionContext: occasionContext)
            } else {
                unmatchedRemove.append(desc)
            }
        }

        var available = host.wardrobeItems.filter { c in !items.contains { $0.id == c.id } }

        // Phase 3: alias-addressed additions
        for alias in addIDs {
            if let match = OutfitMatcher.resolveAlias(alias, in: available) {
                items.append(match)
                added.append("\(match.type) (\(match.primaryColor))")
                available.removeAll { $0.id == match.id }
            } else {
                unmatchedAdd.append(alias)
                AgentTelemetry.recordUnknownAlias(alias, tool: AgentToolName.editOutfit.rawValue)
            }
        }

        // Phase 4: description-addressed additions
        for desc in addDescs {
            AgentTelemetry.recordFuzzyFallback(AgentToolName.editOutfit.rawValue)
            if let match = OutfitMatcher.matchItem(description: desc, in: available) {
                items.append(match)
                added.append("\(match.type) (\(match.primaryColor))")
                available.removeAll { $0.id == match.id }
            } else {
                unmatchedAdd.append(desc)
            }
        }

        return EditResult(
            items: items,
            removed: removed,
            added: added,
            unmatchedRemove: unmatchedRemove,
            unmatchedAdd: unmatchedAdd
        )
    }

    private func recordNegativeSignal(for item: ClothingItem, occasionContext: String?) {
        guard let host,
              let signal = ObservationManager.inferNegativeSignal(removedItem: item, occasionContext: occasionContext),
              let summary = host.styleSummary else { return }
        var observations = summary.behavioralNotesDecoded
        observations = ObservationManager.recordObservation(
            pattern: signal.pattern,
            category: signal.category,
            signal: .negative,
            threshold: 3,
            occasionContext: occasionContext,
            in: observations
        )
        summary.behavioralNotesDecoded = observations
        host.saveIfPossible()
    }

    // MARK: - ID resolution helpers

    private func resolveItemIDs(_ aliases: [String], in items: [ClothingItem]) -> ([ClothingItem], [String]) {
        var matched: [ClothingItem] = []
        var unknown: [String] = []
        for alias in aliases {
            if let item = OutfitMatcher.resolveAlias(alias, in: items) {
                matched.append(item)
            } else {
                unknown.append(alias)
                AgentTelemetry.recordUnknownAlias(alias, tool: AgentToolName.generateOutfit.rawValue)
            }
        }
        return (matched, unknown)
    }

    private func unique(_ items: [ClothingItem]) -> [ClothingItem] {
        var seen = Set<UUID>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
