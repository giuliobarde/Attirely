import SwiftUI
import SwiftData

@Observable
class AgentViewModel {

    // MARK: - Agent Mode

    var effectiveMode: AgentMode = .conversational

    // MARK: - Conversation State

    var messages: [ChatMessage] = []
    var inputText = ""
    var isSending = false
    var errorMessage: String?

    // MARK: - API Message History (ephemeral)

    private var history: [[String: Any]] = []

    // MARK: - Dependencies (set via .onAppear)

    var modelContext: ModelContext?
    var weatherViewModel: WeatherViewModel?
    var userProfile: UserProfile?
    var styleSummaryText: String?
    var styleViewModel: StyleViewModel?
    var styleSummary: StyleSummary?

    // MARK: - Wardrobe Snapshot

    private var wardrobeItems: [ClothingItem] = []
    private var allOutfits: [Outfit] = []

    // MARK: - Task Management

    private(set) var currentTask: Task<Void, Never>?

    var hasUnsavedOutfits: Bool {
        !pendingOutfitItems.isEmpty
    }

    func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
        isSending = false
    }

    // MARK: - Pending Insights

    private var pendingInsights: [(insight: String, confidence: String)] = []

    // MARK: - Pending Outfit Data (deferred until save to avoid SwiftData auto-persistence)

    private var pendingOutfitItems: [UUID: [ClothingItem]] = [:]
    private var pendingOutfitTags: [UUID: [Tag]] = [:]

    func displayItems(for outfit: Outfit) -> [ClothingItem] {
        pendingOutfitItems[outfit.id] ?? outfit.items
    }

    // MARK: - Refresh

    func refreshWardrobe(items: [ClothingItem], outfits: [Outfit]) {
        wardrobeItems = items
        allOutfits = outfits
    }

    func updateStyleContext(from summary: StyleSummary?) {
        styleSummaryText = StyleContextHelper.styleContextString(from: summary)
        styleSummary = summary
    }

    func resolveEffectiveMode(from profile: UserProfile?) {
        guard let profile else { return }
        switch profile.agentMode {
        case .conversational: effectiveMode = .conversational
        case .direct: effectiveMode = .direct
        case .lastUsed: effectiveMode = profile.agentLastActiveMode
        }
    }

    func toggleMode() {
        effectiveMode = (effectiveMode == .conversational) ? .direct : .conversational
        if userProfile?.agentMode == .lastUsed {
            userProfile?.agentLastActiveMode = effectiveMode
            userProfile?.updatedAt = Date()
            try? modelContext?.save()
        }
    }

    // MARK: - Send Message

    func sendUserMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        inputText = ""
        isSending = true
        errorMessage = nil

        // Add user message to UI and history
        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
        history.append(["role": "user", "content": text])

        // Add streaming placeholder
        let streamingID = UUID()
        messages.append(ChatMessage(id: streamingID, role: .assistant, isStreaming: true))

        currentTask = Task {
            await runConversationLoop(streamingID: streamingID)
        }
    }

    func sendStarterMessage(_ text: String) {
        inputText = text
        sendUserMessage()
    }

    // MARK: - Conversation Loop (Streaming)

    private func runConversationLoop(streamingID: UUID) async {
        let apiKey: String
        do {
            apiKey = try ConfigManager.apiKey()
        } catch {
            finalizeMessage(streamingID: streamingID, text: error.localizedDescription)
            isSending = false
            return
        }

        let systemPrompt = buildSystemPrompt()

        do {
            var loopCount = 0
            let maxLoops = 5

            while loopCount < maxLoops {
                guard !Task.isCancelled else { break }
                loopCount += 1

                // Stream one API turn
                var accumulator = ContentBlockAccumulator()
                let eventStream = try await AgentService.streamMessage(
                    history: history,
                    systemPrompt: systemPrompt,
                    tools: AgentService.toolDefinitions,
                    apiKey: apiKey
                )

                for try await event in eventStream {
                    if Task.isCancelled { break }

                    accumulator.apply(event)

                    switch event {
                    case .textDelta(_, let text):
                        appendTextToStreamingMessage(streamingID: streamingID, delta: text)
                    case .messageStop:
                        break
                    default:
                        break
                    }
                }

                guard !Task.isCancelled else { break }

                // Append reconstructed assistant content to history
                let assistantContent = accumulator.rawAssistantContent()
                history.append(["role": "assistant", "content": assistantContent])

                let stopReason = accumulator.stopReason ?? "end_turn"
                let toolCalls = accumulator.finishedToolCalls()

                if stopReason == "end_turn" || toolCalls.isEmpty {
                    finalizeStreamingMessage(streamingID: streamingID)
                    break
                }

                // Execute tools and collect results
                var toolResultBlocks: [[String: Any]] = []
                var outfits: [Outfit] = []
                var foundItems: [ClothingItem] = []
                var insightNote: String?
                var purchaseSuggestions: [PurchaseSuggestionDTO] = []

                for call in toolCalls {
                    if call.name == .suggestPurchases {
                        let (resultContent, suggestions) = await executeSuggestPurchases(
                            SuggestPurchasesInput(from: call.inputJSON)
                        )
                        toolResultBlocks.append([
                            "type": "tool_result",
                            "tool_use_id": call.toolUseID,
                            "content": resultContent
                        ])
                        purchaseSuggestions.append(contentsOf: suggestions)
                    } else {
                        let (resultContent, toolOutfits, toolItems, toolInsight) = await executeTool(call)
                        toolResultBlocks.append([
                            "type": "tool_result",
                            "tool_use_id": call.toolUseID,
                            "content": resultContent
                        ])
                        outfits.append(contentsOf: toolOutfits)
                        foundItems.append(contentsOf: toolItems)
                        if let note = toolInsight { insightNote = note }
                    }
                }

                // Append tool results as user message in history
                history.append(["role": "user", "content": toolResultBlocks])

                // Update streaming message with intermediate tool results
                if !outfits.isEmpty || !foundItems.isEmpty || insightNote != nil || !purchaseSuggestions.isEmpty {
                    updateStreamingMessage(
                        streamingID: streamingID,
                        text: nil,
                        outfits: outfits,
                        wardrobeItems: foundItems,
                        insightNote: insightNote,
                        purchaseSuggestions: purchaseSuggestions
                    )
                }
            }
        } catch {
            if !Task.isCancelled {
                let errorText: String
                if case AnthropicError.overloaded = error {
                    errorText = "Claude is currently overloaded — please try again in a moment."
                } else {
                    errorText = "Something went wrong. Please try again."
                }
                finalizeMessage(streamingID: streamingID, text: errorText)
            }
        }

        isSending = false
    }

    // MARK: - Tool Execution

    private func executeTool(_ call: ToolUseBlock) async -> (String, [Outfit], [ClothingItem], String?) {
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
        }
    }

    private func executeGenerateOutfit(_ input: GenerateOutfitInput) async -> (String, [Outfit], [ClothingItem], String?) {
        guard wardrobeItems.count >= 2 else {
            return ("The user's wardrobe has fewer than 2 items. They need to add more items before generating outfits.", [], [], nil)
        }

        do {
            let apiKey = try ConfigManager.apiKey()
            _ = apiKey // used by AnthropicService internally

            // Resolve must-include items against full wardrobe (before filtering)
            let mustIncludeResolved = input.mustIncludeItems.compactMap { desc in
                matchItem(description: desc, in: wardrobeItems)
            }
            // Map free-form occasion string to OccasionTier and filter items
            let tier = input.occasion.flatMap { OccasionTier(fromString: $0) }
            let filterResult = OccasionFilter.filterItems(wardrobeItems, for: tier)
            let filterContext = OccasionFilter.buildFilterContext(from: filterResult)

            // Re-inject must-include items that were filtered out
            var filteredItems = filterResult.items
            for item in mustIncludeResolved where !filteredItems.contains(where: { $0.id == item.id }) {
                filteredItems.append(item)
            }

            // Score and select candidate items for token efficiency
            let observations = styleSummary?.activeObservations ?? []
            let scorerConfig = RelevanceScorerConfig(
                occasion: tier,
                season: weatherViewModel?.suggestedSeason,
                currentTemp: weatherViewModel?.snapshot?.current.temperature,
                observations: observations,
                allOutfits: allOutfits
            )
            let scoredItems = RelevanceScorer.selectCandidates(from: filteredItems, config: scorerConfig)
            var candidateItems = scoredItems.map(\.item)
            let relevanceHints = Dictionary(uniqueKeysWithValues: scoredItems.map { ($0.item.id, $0.score) })

            // Re-inject must-include items that were scored out
            for item in mustIncludeResolved where !candidateItems.contains(where: { $0.id == item.id }) {
                candidateItems.append(item)
            }

            // Build observation context for prompt injection
            let observationPrompt = ObservationManager.promptString(from: observations, forOccasion: tier)

            let existingItemSets = allOutfits.map { outfit in
                outfit.items.map { $0.id.uuidString }.sorted()
            }

            // Fetch outfit-scoped tags for AI auto-tagging
            let allTags = (try? modelContext?.fetch(FetchDescriptor<Tag>())) ?? []
            let outfitTags = allTags.filter { $0.scope == .outfit }
            let tagNames = outfitTags.map(\.name)

            let mustIncludeIDStrings = Set(mustIncludeResolved.map(\.id.uuidString))

            let suggestions = try await AnthropicService.generateOutfits(
                from: candidateItems,
                occasion: input.occasion,
                season: weatherViewModel?.suggestedSeason,
                weatherContext: weatherViewModel?.weatherContextString,
                comfortPreferences: StyleContextHelper.comfortPreferencesString(from: userProfile),
                styleSummary: styleSummaryText,
                filterContext: filterContext,
                existingOutfitItemSets: existingItemSets,
                availableTagNames: tagNames,
                observationContext: observationPrompt,
                itemRelevanceHints: relevanceHints,
                mustIncludeItemIDs: mustIncludeIDStrings,
                styleMode: userProfile?.styleMode,
                styleDirection: userProfile?.styleDirection
            )

            var createdOutfits: [Outfit] = []
            for suggestion in suggestions {
                var matchedItems = candidateItems.filter {
                    suggestion.itemIDs.contains($0.id.uuidString)
                }

                // Force-add must-include items that the AI omitted
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
                pendingOutfitItems[outfit.id] = matchedItems
                pendingOutfitTags[outfit.id] = resolvedTags

                // Merge client-side + AI wardrobe gap notes
                let mergedGaps = OccasionFilter.mergeGaps(clientSide: filterResult.wardrobeGaps, aiSide: suggestion.wardrobeGaps)
                outfit.wardrobeGaps = Outfit.encodeGaps(mergedGaps)

                createdOutfits.append(outfit)
            }

            if createdOutfits.isEmpty {
                return ("Could not generate a valid outfit from the wardrobe. Some suggested items could not be matched.", [], [], nil)
            }

            let outfit = createdOutfits[0]
            let matchedItems = pendingOutfitItems[outfit.id] ?? []
            let itemSummary = matchedItems.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")
            let resultText = """
            Generated outfit: "\(outfit.displayName)"
            Occasion: \(outfit.occasion ?? "General")
            Items: \(itemSummary)
            Reasoning: \(outfit.reasoning ?? "")
            """

            return (resultText, createdOutfits, [], nil)
        } catch {
            return ("Failed to generate outfit: \(error.localizedDescription)", [], [], nil)
        }
    }

    private func executeSearchOutfits(_ input: SearchOutfitsInput) -> (String, [Outfit], [ClothingItem], String?) {
        var matches = allOutfits

        // Filter by tags if provided
        if !input.tags.isEmpty {
            let normalizedTags = input.tags.map { Tag.normalized($0) }
            matches = matches.filter { outfit in
                normalizedTags.contains { tagName in
                    outfit.tags.contains { $0.name == tagName }
                }
            }
        }

        // Filter by query text if provided
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

        // Sort: favorites first, then by creation date (newest first)
        matches.sort { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return a.createdAt > b.createdAt
        }

        // Limit to a reasonable number
        let top = Array(matches.prefix(5))

        if top.isEmpty {
            return ("No saved outfits found matching this search. I can generate a new outfit for you if you'd like.", [], [], nil)
        }

        var result = "Found \(matches.count) outfit\(matches.count == 1 ? "" : "s"):\n"
        for outfit in top {
            let items = outfit.items.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")
            let tags = outfit.tags.map(\.name).joined(separator: ", ")
            result += "- \"\(outfit.displayName)\" | Items: \(items)"
            if !tags.isEmpty { result += " | Tags: \(tags)" }
            if outfit.isFavorite { result += " ⭐" }
            result += "\n"
        }

        return (result, top, [], nil)
    }

    private static let searchStopWords: Set<String> = [
        "a", "an", "the", "for", "to", "in", "on", "with", "and", "or", "my",
        "any", "some", "that", "this", "those", "these", "of", "is", "are",
        "it", "its", "i", "me", "do", "have", "has", "can", "would", "could",
        "today", "tonight", "tomorrow", "weather", "something", "anything", "items"
    ]

    private func executeSearchWardrobe(_ input: SearchWardrobeInput) -> (String, [Outfit], [ClothingItem], String?) {
        let query = input.query.lowercased()
        let words = query.split(separator: " ").map { String($0) }
            .filter { !Self.searchStopWords.contains($0) }

        guard !words.isEmpty else {
            return ("No items found matching '\(input.query)'.", [], [], nil)
        }

        // Score items by how many query words match (not all-or-nothing)
        let scored = wardrobeItems.compactMap { item -> (ClothingItem, Int)? in
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
            result += "- \(item.type) | \(item.category) | \(item.primaryColor) | \(item.formality) | \(item.itemDescription)\n"
        }

        return (result, [], matches, nil)
    }

    private func executeUpdateStyleInsight(_ input: UpdateStyleInsightInput) -> (String, [Outfit], [ClothingItem], String?) {
        pendingInsights.append((insight: input.insight, confidence: input.confidence))

        // Record as structured observation
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

        if let summary = styleSummary {
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
            try? modelContext?.save()
        }

        return ("Insight recorded.", [], [], input.insight)
    }

    private func executeEditOutfit(_ input: EditOutfitInput) -> (String, [Outfit], [ClothingItem], String?) {
        guard let outfit = resolveOutfit(named: input.outfitName) else {
            return ("Could not find an outfit matching '\(input.outfitName)' in this conversation or wardrobe.", [], [], nil)
        }
        if outfit.modelContext != nil {
            return executeEditSavedOutfitAsCopy(input, source: outfit)
        } else {
            return executeEditConversationOutfit(input, outfit: outfit)
        }
    }

    // Edit an unsaved conversation outfit in place (original behavior).
    private func executeEditConversationOutfit(
        _ input: EditOutfitInput,
        outfit: Outfit
    ) -> (String, [Outfit], [ClothingItem], String?) {
        var currentItems = pendingOutfitItems[outfit.id] ?? outfit.items

        let (updatedItems, removed, added) = applyItemEdits(
            remove: input.removeItems,
            add: input.addItems,
            to: currentItems,
            occasionContext: outfit.occasion
        )
        currentItems = updatedItems

        // Apply metadata directly (safe — not yet in SwiftData)
        if let newName = input.newName, !newName.isEmpty { outfit.name = newName }
        if let newOccasion = input.newOccasion, !newOccasion.isEmpty { outfit.occasion = newOccasion }

        pendingOutfitItems[outfit.id] = currentItems

        let warnings = OutfitLayerOrder.warnings(for: currentItems)

        // Force UI refresh on the message containing this outfit
        if let msgIndex = messages.firstIndex(where: { $0.outfits.contains(where: { $0.id == outfit.id }) }) {
            messages[msgIndex].outfits = messages[msgIndex].outfits
        }

        var summary = "Updated outfit \"\(outfit.displayName)\"."
        if !removed.isEmpty { summary += " Removed: \(removed.joined(separator: ", "))." }
        if !added.isEmpty { summary += " Added: \(added.joined(separator: ", "))." }
        let itemList = currentItems.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")
        summary += " Current items (\(currentItems.count)): \(itemList)."
        if !warnings.isEmpty { summary += " Warnings: \(warnings.joined(separator: "; "))." }

        return (summary, [], [], nil)
    }

    // Edit a saved wardrobe outfit by creating a new copy — original is never modified.
    private func executeEditSavedOutfitAsCopy(
        _ input: EditOutfitInput,
        source: Outfit
    ) -> (String, [Outfit], [ClothingItem], String?) {
        let copy = Outfit(
            name: (input.newName?.isEmpty == false ? input.newName : nil) ?? source.name,
            occasion: (input.newOccasion?.isEmpty == false ? input.newOccasion : nil) ?? source.occasion,
            reasoning: source.reasoning,
            isAIGenerated: source.isAIGenerated,
            items: [],
            tags: []
        )

        let (updatedItems, removed, added) = applyItemEdits(
            remove: input.removeItems,
            add: input.addItems,
            to: source.items,
            occasionContext: source.occasion
        )

        pendingOutfitItems[copy.id] = updatedItems
        pendingOutfitTags[copy.id] = source.tags

        let warnings = OutfitLayerOrder.warnings(for: updatedItems)
        let itemList = updatedItems.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")

        var summary = "Created a new outfit based on \"\(source.displayName)\". The original was not modified."
        if !removed.isEmpty { summary += " Removed: \(removed.joined(separator: ", "))." }
        if !added.isEmpty { summary += " Added: \(added.joined(separator: ", "))." }
        summary += " New outfit items (\(updatedItems.count)): \(itemList)."
        if !warnings.isEmpty { summary += " Warnings: \(warnings.joined(separator: "; "))." }
        summary += " Show the new outfit to the user and offer to save it."

        return (summary, [copy], [], nil)
    }

    private func executeSuggestPurchases(_ input: SuggestPurchasesInput) async -> (String, [PurchaseSuggestionDTO]) {
        guard !wardrobeItems.isEmpty else {
            return ("The user's wardrobe is empty. Ask them to add some items first before suggesting purchases.", [])
        }

        do {
            let suggestions = try await AnthropicService.suggestPurchases(
                wardrobeItems: wardrobeItems,
                category: input.category,
                styleSummary: styleSummaryText,
                styleMode: userProfile?.styleMode,
                styleDirection: userProfile?.styleDirection
            )

            guard !suggestions.isEmpty else {
                return ("No purchase suggestions could be generated.", [])
            }

            // Build tool result text so Claude can comment naturally
            var resultText = "Generated \(suggestions.count) purchase suggestion\(suggestions.count == 1 ? "" : "s"):\n"
            for (i, s) in suggestions.enumerated() {
                resultText += "\(i + 1). \(s.description) (\(s.category)) — pairs with \(s.wardrobeCompatibilityCount) items\n"
            }
            resultText += "Display these suggestions to the user as structured cards."

            return (resultText, suggestions)
        } catch {
            return ("Failed to generate suggestions: \(error.localizedDescription)", [])
        }
    }

    private func resolveOutfit(named name: String) -> Outfit? {
        let allConversationOutfits = messages.flatMap(\.outfits).reversed()
        if !name.isEmpty {
            let lowered = name.lowercased()
            if let match = allConversationOutfits.first(where: {
                $0.displayName.lowercased().contains(lowered) ||
                ($0.occasion?.lowercased().contains(lowered) ?? false)
            }) {
                return match
            }
        }
        // Fallback: most recent unsaved outfit, or just the most recent conversation outfit
        if let conversationFallback = allConversationOutfits.first(where: { pendingOutfitItems[$0.id] != nil })
            ?? allConversationOutfits.first {
            return conversationFallback
        }
        // Final fallback: search saved outfits by name (only when name is explicit)
        if !name.isEmpty {
            let lowered = name.lowercased()
            return allOutfits.first {
                $0.displayName.lowercased().contains(lowered) ||
                ($0.occasion?.lowercased().contains(lowered) ?? false)
            }
        }
        return nil
    }

    // Shared helper: apply remove/add operations to an item list, recording behavioral signals.
    private func applyItemEdits(
        remove removeDescs: [String],
        add addDescs: [String],
        to startItems: [ClothingItem],
        occasionContext: String?
    ) -> (items: [ClothingItem], removed: [String], added: [String]) {
        var items = startItems
        var removed: [String] = []
        var added: [String] = []

        for desc in removeDescs {
            if let match = matchItem(description: desc, in: items) {
                items.removeAll { $0.id == match.id }
                removed.append("\(match.type) (\(match.primaryColor))")
                if let signal = ObservationManager.inferNegativeSignal(removedItem: match, occasionContext: occasionContext),
                   let summary = styleSummary {
                    var observations = summary.behavioralNotesDecoded
                    observations = ObservationManager.recordObservation(
                        pattern: signal.pattern, category: signal.category, signal: .negative,
                        threshold: 3, occasionContext: occasionContext, in: observations
                    )
                    summary.behavioralNotesDecoded = observations
                    try? modelContext?.save()
                }
            }
        }

        let available = wardrobeItems.filter { c in !items.contains { $0.id == c.id } }
        for desc in addDescs {
            if let match = matchItem(description: desc, in: available) {
                items.append(match)
                added.append("\(match.type) (\(match.primaryColor))")
            }
        }

        return (items, removed, added)
    }

    private func matchItem(description: String, in items: [ClothingItem]) -> ClothingItem? {
        let words = description.lowercased().split(separator: " ").map(String.init)
        let scored = items.map { item in
            let fields = "\(item.type) \(item.primaryColor) \(item.category) \(item.fabricEstimate)".lowercased()
            let score = words.filter { fields.contains($0) }.count
            return (item, score)
        }
        return scored.filter { $0.1 > 0 }.max(by: { $0.1 < $1.1 })?.0
    }

    // MARK: - Message Management

    private func appendTextToStreamingMessage(streamingID: UUID, delta: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        if messages[index].text == nil {
            messages[index].text = delta
            messages[index].isStreaming = false // hide dots once first token arrives
        } else {
            messages[index].text?.append(delta)
        }
    }

    private func finalizeStreamingMessage(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].isStreaming = false
    }

    private func finalizeMessage(streamingID: UUID, text: String?) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].text = text
        messages[index].isStreaming = false
    }

    private func updateStreamingMessage(
        streamingID: UUID,
        text: String?,
        outfits: [Outfit],
        wardrobeItems: [ClothingItem],
        insightNote: String?,
        purchaseSuggestions: [PurchaseSuggestionDTO] = []
    ) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        if let text { messages[index].text = text }
        messages[index].outfits.append(contentsOf: outfits)
        messages[index].wardrobeItems.append(contentsOf: wardrobeItems)
        if let insightNote { messages[index].insightNote = insightNote }
        messages[index].purchaseSuggestions.append(contentsOf: purchaseSuggestions)
    }

    // MARK: - Save Outfit

    func saveOutfit(_ outfit: Outfit) {
        guard let modelContext else { return }
        if let items = pendingOutfitItems.removeValue(forKey: outfit.id) {
            outfit.items = items
        }
        if let tags = pendingOutfitTags.removeValue(forKey: outfit.id) {
            outfit.tags = tags
        }
        captureWeatherSnapshot(on: outfit)
        modelContext.insert(outfit)
        try? modelContext.save()
        notifyStyleAnalysis()
    }

    private func captureWeatherSnapshot(on outfit: Outfit) {
        if let snapshot = weatherViewModel?.snapshot {
            outfit.weatherTempAtCreation = snapshot.current.temperature
            outfit.weatherFeelsLikeAtCreation = snapshot.current.feelsLike
            outfit.seasonAtCreation = weatherViewModel?.suggestedSeason
        }
        outfit.monthAtCreation = Calendar.current.component(.month, from: Date())
    }

    private func notifyStyleAnalysis() {
        guard let context = modelContext else { return }
        let items = (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? []
        let outfits = (try? context.fetch(FetchDescriptor<Outfit>())) ?? []
        styleViewModel?.analyzeStyle(items: items, outfits: outfits, profile: userProfile)
    }

    // MARK: - Clear

    func clearConversation() {
        messages = []
        history = []
        pendingInsights = []
        pendingOutfitItems = [:]
        pendingOutfitTags = [:]
        errorMessage = nil
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        var prompt = """
        You are the Attirely style agent — a warm, knowledgeable personal stylist who knows \
        this user's entire wardrobe. You help them decide what to wear, explore their style, \
        and discover new outfit combinations.

        GUIDELINES:
        - Be conversational and concise. Keep responses to 1-3 short paragraphs unless the user asks for detail.
        - Never invent items the user doesn't own. If you're unsure, search first.
        - Reference items by their type and color (e.g. "your navy blazer") rather than IDs.
        - When the user explicitly states a style preference or dislike, use updateStyleInsight to record it. Do not announce that you're recording it — just acknowledge naturally.
        - When the user removes items from outfits, expresses dislike, or rejects suggestions, use updateStyleInsight to record the behavioral pattern as a negative signal. Include the category and signal fields when you can determine them.
        - If you notice recurring patterns in the user's choices across the conversation (e.g., they always pick dark colors, avoid certain fabrics), record these as low-confidence insights.

        INTENT DETECTION — choosing the right tool:
        - When the user wants something NEW, DIFFERENT, or a SURPRISE ("give me a new outfit", "surprise me", "something I haven't tried", "create an outfit for…"), use the generateOutfit tool.
        - When the user wants something FAMILIAR, a GO-TO, or PREVIOUSLY WORN ("what do I usually wear", "my go-to work outfit", "something I've worn before", "a classic", "what's my favorite…"), use the searchOutfits tool to find existing saved outfits.
        - When the user asks about specific ITEMS they own ("do I have any blazers?", "what blue tops do I have?"), use the searchWardrobe tool.
        - When the user wants to MODIFY an outfit — from this conversation OR a saved outfit they reference by name ("swap the shoes on my work outfit", "update my Casual Friday look", "add a blazer to my dinner outfit") — use the editOutfit tool. For saved outfits, a new variant is created and the original is preserved.
        - When the user states a preference/dislike OR you observe a behavioral pattern from their edits/rejections, use updateStyleInsight. Include category and signal when you can determine them.
        - When the user wants an outfit built around a SPECIFIC ITEM or COLOR ("build around my leather jacket", "something red"), use searchWardrobe first to find matching items, then use generateOutfit with must_include_items to anchor on those pieces.
        - When the user asks what they should BUY, what to ADD to their wardrobe, what's WORTH PURCHASING, or what new item would unlock more outfits ("what should I buy?", "what's missing that I should get?", "what new piece would work with what I have?"), use the suggestPurchases tool. If they specify a category (e.g. "a jacket", "trousers"), pass it as the category parameter.
        \(ambiguousIntentRule)
        - If searchOutfits returns no results, explain that and offer to generate something new instead.
        """

        // Mode-specific behavior block
        prompt += "\n\n\(modeBehaviorBlock)"

        // Weather context
        if let weather = weatherViewModel?.weatherContextString {
            prompt += "\n\nCURRENT WEATHER:\n\(weather)"
        } else {
            prompt += "\n\nCURRENT WEATHER: Not available."
        }

        // Temperature display preference — avoid degree symbol to prevent UTF-8 encoding corruption
        let preferredUnit = userProfile?.temperatureUnit ?? .celsius
        let unitLabel = preferredUnit == .fahrenheit ? "Fahrenheit (F)" : "Celsius (C)"
        prompt += "\n\nTEMPERATURE DISPLAY: Weather data above is in Celsius. When mentioning temperatures in your responses, convert and display in \(unitLabel)."

        // Comfort preferences
        if let comfort = StyleContextHelper.comfortPreferencesString(from: userProfile) {
            prompt += "\n\nUSER COMFORT PREFERENCES:\n\(comfort)"
        }

        // Style mode
        if let mode = userProfile?.styleMode {
            switch mode {
            case .improve:
                var hint = "\n\nSTYLE MODE: Improve — when suggesting outfits or discussing style, favor polished and refined combinations over casual ones."
                if let direction = userProfile?.styleDirection {
                    hint += " Style direction: \(direction.displayName)."
                }
                prompt += hint
            case .expand:
                prompt += "\n\nSTYLE MODE: Expand — when suggesting outfits or discussing style, stay true to the user's detected personal aesthetic rather than pushing toward a conventional ideal."
            }
        }

        // Style summary
        if let style = styleSummaryText {
            prompt += "\n\nSTYLE PROFILE:\n\(style)"
        }

        // Wardrobe overview (counts only — full items loaded on demand via tools)
        let categoryCounts = Dictionary(grouping: wardrobeItems, by: \.category)
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")

        prompt += "\n\nWARDROBE OVERVIEW:\n\(wardrobeItems.count) items total."
        if !categoryCounts.isEmpty {
            prompt += " Categories: \(categoryCounts)."
        }

        // Outfit overview
        let favoriteCount = allOutfits.filter(\.isFavorite).count
        prompt += "\n\nOUTFIT OVERVIEW:\n\(allOutfits.count) saved outfits"
        if favoriteCount > 0 {
            prompt += " (\(favoriteCount) favorited)"
        }
        prompt += "."

        // Pending insights from this session
        if !pendingInsights.isEmpty {
            prompt += "\n\nINSIGHTS CAPTURED THIS SESSION:"
            for insight in pendingInsights {
                prompt += "\n- \(insight.insight)"
            }
        }

        // Behavioral observations (persistent across conversations)
        if let observations = styleSummary?.activeObservations,
           let observationPrompt = ObservationManager.promptString(from: observations) {
            prompt += "\n\nUSER BEHAVIORAL PATTERNS (learned from past conversations):\n\(observationPrompt)"
            prompt += "\nUse these observations to inform your suggestions. If the user contradicts a pattern, that's fine — update your understanding."
        }

        return prompt
    }

    private var ambiguousIntentRule: String {
        switch effectiveMode {
        case .conversational:
            return """
            - When the phrasing is AMBIGUOUS ("what should I wear today", "dress me up"), do NOT \
            immediately call generateOutfit. Instead, explore with searchWardrobe first and discuss \
            options before generating. EXCEPTION: if the user specifies a clear occasion AND has no \
            ambiguous preferences AND weather conditions are moderate, you may generate directly.
            """
        case .direct, .lastUsed:
            return "- When the phrasing is AMBIGUOUS (\"what should I wear today\"), default to generateOutfit."
        }
    }

    private var modeBehaviorBlock: String {
        switch effectiveMode {
        case .conversational:
            return """
            BEHAVIOR MODE: CONVERSATIONAL
            - For ambiguous outfit requests, do NOT call generateOutfit on your first turn.
            - Instead, use searchWardrobe to explore what's available for the context (weather, occasion, color).
            - Ask clarifying questions when the request is vague: occasion, formality, color preferences.
            - Proactively flag mismatches between the request and reality: limited color options, \
            weather conflicts, seasonal issues. For example, if the user asks for red items but you \
            only find a heavy sweatshirt in summer heat, point this out and ask if they'd like to proceed.
            - When the user references specific items or colors ("my leather jacket", "something red"), \
            always searchWardrobe first to find exact matches and assess their suitability.
            - CRITICAL — ANCHOR CARRYOVER: When you've discussed specific items or colors with the user \
            and they confirm (e.g., you found red Jordan 1s and the user says "casual day"), you MUST \
            pass those discussed items in must_include_items when calling generateOutfit. Use the item's \
            type and primary color (e.g., "red high top sneakers"). Do NOT lose the color/item context \
            from earlier in the conversation — the user expects the generated outfit to feature what \
            was discussed, not a different color or item.
            - Summarize your plan briefly before calling generateOutfit ("I'll put together a casual \
            look anchored on your navy blazer — let me build something around it").
            - FAST-TRACK: If the user specifies a clear occasion AND has no ambiguous preferences \
            AND the wardrobe has suitable items for the current weather, go ahead and generate directly.
            """
        case .direct, .lastUsed:
            return """
            BEHAVIOR MODE: DIRECT
            - Default to generateOutfit immediately for any outfit request, including ambiguous ones.
            - Be efficient: generate first, discuss after if the user wants changes.
            - Skip clarifying questions unless the request is impossible to fulfill.
            - When the user references specific items, pass them via must_include_items with your best \
            description match based on type and color.
            """
        }
    }

}
