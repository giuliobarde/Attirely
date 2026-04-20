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

    // Item-ID sets from outfits generated during the active chat session.
    // Merged with saved-outfit sets when calling generateOutfits so the agent
    // cannot repeat an outfit it produced earlier in the same conversation.
    private var conversationGeneratedItemSets: [[String]] = []

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

    // Message IDs whose next text delta should be preceded by a paragraph break.
    // Set after a tool-using turn ends so Turn N+1 text doesn't concatenate with Turn N text.
    private var pendingSeparatorMessageIDs: Set<UUID> = []

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

    // copy.id → source.id — lets "Update Original" know which saved outfit to mutate
    private var sourceOutfitIDForCopy: [UUID: UUID] = [:]

    func displayItems(for outfit: Outfit) -> [ClothingItem] {
        pendingOutfitItems[outfit.id] ?? outfit.items
    }

    func isCopyOfSavedOutfit(_ outfit: Outfit) -> Bool {
        sourceOutfitIDForCopy[outfit.id] != nil
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

    // Hard cap on tool-use iterations. Raised from 5 so legitimate long tool chains
    // (e.g. suggestPurchases → searchWardrobe → generateOutfit → respond) don't get
    // cut off. The real guard is the repeat detector in the loop body.
    private static let maxLoops = 10

    // Exponential backoff for retryable transient errors. Max 3 attempts total.
    private static let retryDelaysNs: [UInt64] = [1_000_000_000, 3_000_000_000, 7_000_000_000]
    private static let maxRetryAttempts = 3

    private func runConversationLoop(streamingID: UUID) async {
        let apiKey: String
        do {
            apiKey = try ConfigManager.apiKey()
        } catch {
            finalizeMessage(streamingID: streamingID, text: error.localizedDescription)
            isSending = false
            return
        }

        let cachedSystemPrompt = buildCachedSystemPrompt()

        do {
            var loopCount = 0
            var seenCallSignatures: Set<String> = []
            var wrapUpMode = false
            var completedNormally = false

            while loopCount < Self.maxLoops {
                guard !Task.isCancelled else { break }
                loopCount += 1

                // Clear per-turn transient UI state (previous turn's tool phrase, etc.)
                clearToolStatus(streamingID: streamingID)

                // Rebuild the fresh block every turn (weather/observations/pending insights
                // may have changed). The cached block is stable across the session.
                let freshSystemPrompt = buildFreshSystemPrompt()
                let toolsForTurn: [[String: Any]] = wrapUpMode ? [] : AgentService.toolDefinitions

                let accumulator = try await streamOneTurn(
                    history: history,
                    cachedSystemPrompt: cachedSystemPrompt,
                    freshSystemPrompt: freshSystemPrompt,
                    tools: toolsForTurn,
                    apiKey: apiKey,
                    streamingID: streamingID
                )

                guard !Task.isCancelled else { break }

                // Append reconstructed assistant content to history
                let assistantContent = accumulator.rawAssistantContent()
                history.append(["role": "assistant", "content": assistantContent])

                let stopReason = accumulator.stopReason ?? "end_turn"
                let toolCalls = accumulator.finishedToolCalls()

                // Non-tool stop reasons, or a wrap-up turn finishing: exit cleanly.
                // (During wrap-up mode tools=[] so the model can't legitimately call tools;
                // if it somehow does, treat it as a normal exit to avoid an infinite loop.)
                if stopReason != "tool_use" || wrapUpMode {
                    switch stopReason {
                    case "end_turn", "stop_sequence":
                        break
                    case "max_tokens":
                        setWarning(streamingID: streamingID, text: "Response was cut off (token limit).")
                    case "refusal":
                        setWarning(streamingID: streamingID, text: "Request declined.")
                    case "pause_turn":
                        setWarning(streamingID: streamingID, text: "Response paused.")
                    default:
                        break
                    }
                    finalizeStreamingMessage(streamingID: streamingID)
                    completedNormally = true
                    break
                }

                // stop_reason == "tool_use" but no parseable tool calls — defensive exit to avoid looping.
                if toolCalls.isEmpty {
                    finalizeStreamingMessage(streamingID: streamingID)
                    completedNormally = true
                    break
                }

                // Runaway detector: if a (tool, normalized_input) tuple repeats within
                // this conversation turn, fall back to a wrap-up turn next iteration.
                var hadRepeat = false
                for call in toolCalls {
                    let sig = signatureFor(call)
                    if !seenCallSignatures.insert(sig).inserted {
                        hadRepeat = true
                        print("[AgentRunaway] Repeat call detected: \(call.name.rawValue) input=\(sig)")
                    }
                }

                // Execute tools and collect results
                var toolResultBlocks: [[String: Any]] = []
                var outfits: [Outfit] = []
                var foundItems: [ClothingItem] = []
                var insightNote: String?
                var purchaseSuggestions: [PurchaseSuggestionDTO] = []
                var pendingQuestion: AgentQuestion?

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
                    } else if call.name == .askUserQuestion {
                        let input = AskUserQuestionInput(from: call.inputJSON)
                        pendingQuestion = AgentQuestion(
                            id: streamingID,
                            toolUseID: call.toolUseID,
                            question: input.question,
                            options: input.options,
                            allowsOther: input.allowsOther,
                            multiSelect: input.multiSelect
                        )
                        toolResultBlocks.append([
                            "type": "tool_result",
                            "tool_use_id": call.toolUseID,
                            "content": "Question posted to the user. Wait for their reply as a new user message — do not respond further this turn."
                        ])
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

                // Mark a paragraph break before the next turn's text deltas so
                // pre-tool narration and post-tool response don't run together.
                pendingSeparatorMessageIDs.insert(streamingID)

                // Update streaming message with intermediate tool results
                if !outfits.isEmpty || !foundItems.isEmpty || insightNote != nil || !purchaseSuggestions.isEmpty || pendingQuestion != nil {
                    updateStreamingMessage(
                        streamingID: streamingID,
                        text: nil,
                        outfits: outfits,
                        wardrobeItems: foundItems,
                        insightNote: insightNote,
                        purchaseSuggestions: purchaseSuggestions,
                        question: pendingQuestion
                    )
                }

                if hadRepeat {
                    wrapUpMode = true
                    print("[AgentRunaway] Entering wrap-up mode after repeat")
                }
            }

            // Safety-net wrap-up: if we hit maxLoops while the model was still in tool-use,
            // issue one final call with tools:[] so the model produces a clean text close-out.
            if !completedNormally && !Task.isCancelled && loopCount >= Self.maxLoops && !wrapUpMode {
                print("[AgentRunaway] Hit maxLoops=\(Self.maxLoops) — forcing wrap-up turn")
                clearToolStatus(streamingID: streamingID)
                let freshSystemPrompt = buildFreshSystemPrompt()
                let accumulator = try await streamOneTurn(
                    history: history,
                    cachedSystemPrompt: cachedSystemPrompt,
                    freshSystemPrompt: freshSystemPrompt,
                    tools: [],
                    apiKey: apiKey,
                    streamingID: streamingID
                )
                let assistantContent = accumulator.rawAssistantContent()
                history.append(["role": "assistant", "content": assistantContent])
                finalizeStreamingMessage(streamingID: streamingID)
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

    // Stream one API turn with retry + backoff on transient errors. Retries only while
    // no text delta has been emitted yet this turn — once the bubble starts filling in,
    // restarting would visibly rewind the user's screen.
    private func streamOneTurn(
        history: [[String: Any]],
        cachedSystemPrompt: String,
        freshSystemPrompt: String,
        tools: [[String: Any]],
        apiKey: String,
        streamingID: UUID
    ) async throws -> ContentBlockAccumulator {
        var attempt = 0

        while true {
            attempt += 1
            clearRetryStatus(streamingID: streamingID)

            var accumulator = ContentBlockAccumulator()
            var anyTextEmitted = false

            do {
                let eventStream = try await AgentService.streamMessage(
                    history: history,
                    cachedSystemPrompt: cachedSystemPrompt,
                    freshSystemPrompt: freshSystemPrompt,
                    tools: tools,
                    apiKey: apiKey
                )

                for try await event in eventStream {
                    if Task.isCancelled { break }

                    accumulator.apply(event)

                    switch event {
                    case .textDelta(_, let text):
                        anyTextEmitted = true
                        appendTextToStreamingMessage(streamingID: streamingID, delta: text)
                    case .toolUseStart(_, _, let name):
                        setToolStatus(streamingID: streamingID, name: name)
                    case .messageStop:
                        break
                    default:
                        break
                    }
                }

                return accumulator
            } catch {
                if Task.isCancelled { throw error }
                if anyTextEmitted { throw error }
                guard attempt < Self.maxRetryAttempts, isRetryable(error) else {
                    throw error
                }

                let delay = Self.retryDelaysNs[min(attempt - 1, Self.retryDelaysNs.count - 1)]
                setRetryStatus(
                    streamingID: streamingID,
                    text: "Retrying… (attempt \(attempt + 1)/\(Self.maxRetryAttempts))"
                )
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        switch error {
        case AnthropicError.overloaded, AnthropicError.networkError:
            return true
        case AnthropicError.apiError(let code, _):
            return code == 429 || (500..<600).contains(code)
        default:
            return false
        }
    }

    private func signatureFor(_ call: ToolUseBlock) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: call.inputJSON,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? ""
        return "\(call.name.rawValue)|\(json)"
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
        case .askUserQuestion:
            return ("askUserQuestion is handled separately.", [], [], nil)
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

            let savedOutfitItemSets = allOutfits.map { outfit in
                outfit.items.map { $0.id.uuidString }.sorted()
            }
            let existingItemSets = savedOutfitItemSets + conversationGeneratedItemSets

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

                // Track this combination so subsequent turns in the same chat don't repeat it.
                let generatedItemIDs = matchedItems.map { $0.id.uuidString }.sorted()
                conversationGeneratedItemSets.append(generatedItemIDs)

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
        } catch AnthropicError.allSuggestionsDuplicate {
            let message = AnthropicError.allSuggestionsDuplicate.errorDescription ?? "No new outfit combination available."
            return ("Every suggestion the stylist proposed duplicated an outfit the user already has. Tell the user: \(message)", [], [], nil)
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
            return executeEditSavedOutfitAsProposal(input, source: outfit)
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

        let (updatedItems, removed, added, unmatchedRemove, unmatchedAdd) = applyItemEdits(
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

        refreshMessageContaining(outfitID: outfit.id)

        var summary = "Updated outfit \"\(outfit.displayName)\"."
        if !removed.isEmpty { summary += " Removed: \(removed.joined(separator: ", "))." }
        if !added.isEmpty { summary += " Added: \(added.joined(separator: ", "))." }
        if !unmatchedRemove.isEmpty { summary += " Could not find in outfit: \(unmatchedRemove.joined(separator: ", "))." }
        if !unmatchedAdd.isEmpty { summary += " Could not find in wardrobe: \(unmatchedAdd.joined(separator: ", "))." }
        let itemList = currentItems.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")
        summary += " Current items (\(currentItems.count)): \(itemList)."
        if !warnings.isEmpty { summary += " Warnings: \(warnings.joined(separator: "; "))." }

        return (summary, [], [], nil)
    }

    // Propose an edit to a saved wardrobe outfit. Renders as an ephemeral copy in the chat;
    // the user picks via buttons whether to update the original or save as a new outfit.
    private func executeEditSavedOutfitAsProposal(
        _ input: EditOutfitInput,
        source: Outfit
    ) -> (String, [Outfit], [ClothingItem], String?) {
        let (updatedItems, removed, added, unmatchedRemove, unmatchedAdd) = applyItemEdits(
            remove: input.removeItems,
            add: input.addItems,
            to: source.items,
            occasionContext: source.occasion
        )

        let nameChanged = !(input.newName?.isEmpty ?? true)
        let occasionChanged = !(input.newOccasion?.isEmpty ?? true)

        // Short-circuit: nothing actually changed. Don't render a misleading card; tell Claude to clarify.
        if removed.isEmpty && added.isEmpty && !nameChanged && !occasionChanged {
            var msg = "No changes were applied to \"\(source.displayName)\"."
            if !unmatchedRemove.isEmpty { msg += " Could not locate \(unmatchedRemove.joined(separator: ", ")) in the outfit." }
            if !unmatchedAdd.isEmpty { msg += " Could not locate \(unmatchedAdd.joined(separator: ", ")) in the wardrobe." }
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

        pendingOutfitItems[copy.id] = updatedItems
        pendingOutfitTags[copy.id] = source.tags
        sourceOutfitIDForCopy[copy.id] = source.id

        let warnings = OutfitLayerOrder.warnings(for: updatedItems)
        let itemList = updatedItems.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")

        var summary = "Proposed an edit to the saved outfit \"\(source.displayName)\"."
        if !removed.isEmpty { summary += " Removed: \(removed.joined(separator: ", "))." }
        if !added.isEmpty { summary += " Added: \(added.joined(separator: ", "))." }
        if !unmatchedRemove.isEmpty { summary += " Could not find in outfit: \(unmatchedRemove.joined(separator: ", "))." }
        if !unmatchedAdd.isEmpty { summary += " Could not find in wardrobe: \(unmatchedAdd.joined(separator: ", "))." }
        summary += " Proposed items (\(updatedItems.count)): \(itemList)."
        if !warnings.isEmpty { summary += " Warnings: \(warnings.joined(separator: "; "))." }
        summary += " The user will choose whether to update the original or save as a new outfit via buttons under the card — simply introduce the variant. Do not say the edit failed, was not applied, or that a copy was made."

        return (summary, [copy], [], nil)
    }

    // Apply an ephemeral copy's fields to its source saved outfit and persist to SwiftData.
    func updateOriginalFromCopy(_ copy: Outfit) {
        guard let sourceID = sourceOutfitIDForCopy[copy.id],
              let source = allOutfits.first(where: { $0.id == sourceID }) else { return }

        let copyItems = pendingOutfitItems[copy.id] ?? copy.items
        let copyTags = pendingOutfitTags[copy.id] ?? copy.tags

        source.items = copyItems
        source.tags = copyTags
        if let newName = copy.name, !newName.isEmpty { source.name = newName }
        if let newOccasion = copy.occasion, !newOccasion.isEmpty { source.occasion = newOccasion }

        try? modelContext?.save()
        notifyStyleAnalysis()

        pendingOutfitItems.removeValue(forKey: copy.id)
        pendingOutfitTags.removeValue(forKey: copy.id)
        sourceOutfitIDForCopy.removeValue(forKey: copy.id)

        if let msgIndex = messages.firstIndex(where: { $0.outfits.contains(where: { $0.id == copy.id }) }) {
            var msg = messages[msgIndex]
            msg.outfits.removeAll { $0.id == copy.id }
            messages[msgIndex] = msg
        }
        refreshMessageContaining(outfitID: source.id)
    }

    private func refreshMessageContaining(outfitID: UUID) {
        guard let msgIndex = messages.firstIndex(where: { $0.outfits.contains(where: { $0.id == outfitID }) }) else { return }
        var msg = messages[msgIndex]
        msg.outfits = msg.outfits.map { $0 }
        messages[msgIndex] = msg
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
    ) -> (items: [ClothingItem], removed: [String], added: [String], unmatchedRemove: [String], unmatchedAdd: [String]) {
        var items = startItems
        var removed: [String] = []
        var added: [String] = []
        var unmatchedRemove: [String] = []
        var unmatchedAdd: [String] = []

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
            } else {
                unmatchedRemove.append(desc)
            }
        }

        let available = wardrobeItems.filter { c in !items.contains { $0.id == c.id } }
        for desc in addDescs {
            if let match = matchItem(description: desc, in: available) {
                items.append(match)
                added.append("\(match.type) (\(match.primaryColor))")
            } else {
                unmatchedAdd.append(desc)
            }
        }

        return (items, removed, added, unmatchedRemove, unmatchedAdd)
    }

    private func matchItem(description: String, in items: [ClothingItem]) -> ClothingItem? {
        // Fast path: if any token parses as a UUID matching a candidate, use it. Current code
        // doesn't expose UUIDs to the agent, but this self-heals if one ever leaks through a tool
        // result or system prompt and lets us adopt ID-based addressing later without touching this path.
        for token in description.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
            if let uuid = UUID(uuidString: String(token)),
               let match = items.first(where: { $0.id == uuid }) {
                return match
            }
        }

        let descWords = Self.normalizeMatchWords(description)
        guard !descWords.isEmpty else { return nil }

        let scored = items.map { item -> (ClothingItem, Int) in
            let fieldText = [
                item.type, item.primaryColor, item.secondaryColor ?? "",
                item.category, item.pattern, item.fabricEstimate,
                item.itemDescription
            ].joined(separator: " ")
            let fieldWords = Self.normalizeMatchWords(fieldText)
            let score = descWords.filter { fieldWords.contains($0) }.count
            return (item, score)
        }
        return scored.filter { $0.1 > 0 }.max(by: { $0.1 < $1.1 })?.0
    }

    private static let matchStopWords: Set<String> = [
        "the", "a", "an", "my", "your", "with", "and", "of", "in", "on"
    ]

    private static func normalizeMatchWords(_ text: String) -> Set<String> {
        let tokens = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !matchStopWords.contains($0) }
        return Set(tokens.map(normalizeToken))
    }

    // Collapses common plural/inflected suffixes so "loafers"/"loafer" and "shoes"/"shoe" match.
    private nonisolated static func normalizeToken(_ t: String) -> String {
        if t.count > 4, t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.count > 3, t.hasSuffix("es") { return String(t.dropLast(2)) }
        if t.count > 3, t.hasSuffix("s") { return String(t.dropLast()) }
        return t
    }

    // MARK: - Message Management

    private func appendTextToStreamingMessage(streamingID: UUID, delta: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        var effectiveDelta = delta
        if pendingSeparatorMessageIDs.contains(streamingID) {
            pendingSeparatorMessageIDs.remove(streamingID)
            if let existing = messages[index].text, !existing.isEmpty {
                effectiveDelta = "\n\n" + delta
            }
        }
        if messages[index].text == nil {
            messages[index].text = effectiveDelta
            messages[index].isStreaming = false // hide dots once first token arrives
            messages[index].toolStatus = nil
            messages[index].retryStatus = nil
        } else {
            messages[index].text?.append(effectiveDelta)
        }
    }

    private func finalizeStreamingMessage(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].isStreaming = false
        messages[index].toolStatus = nil
        messages[index].retryStatus = nil
    }

    private func setWarning(streamingID: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].warning = text
    }

    private func setToolStatus(streamingID: UUID, name: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].toolStatus = phraseForTool(name)
    }

    private func clearToolStatus(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].toolStatus = nil
    }

    private func setRetryStatus(streamingID: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].retryStatus = text
    }

    private func clearRetryStatus(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].retryStatus = nil
    }

    private func phraseForTool(_ name: String) -> String? {
        switch name {
        case "searchWardrobe":     return "Searching your wardrobe…"
        case "searchOutfits":      return "Looking through your saved outfits…"
        case "generateOutfit":     return "Building an outfit…"
        case "editOutfit":         return "Reworking the outfit…"
        case "suggestPurchases":   return "Considering what to add…"
        case "updateStyleInsight": return nil
        case "askUserQuestion":    return nil
        default:                   return nil
        }
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
        purchaseSuggestions: [PurchaseSuggestionDTO] = [],
        question: AgentQuestion? = nil
    ) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        if let text { messages[index].text = text }
        messages[index].outfits.append(contentsOf: outfits)
        messages[index].wardrobeItems.append(contentsOf: wardrobeItems)
        if let insightNote { messages[index].insightNote = insightNote }
        messages[index].purchaseSuggestions.append(contentsOf: purchaseSuggestions)
        if let question { messages[index].question = question }
    }

    func submitQuestionAnswer(messageID: UUID, answer: AgentQuestionAnswer) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              var q = messages[idx].question,
              q.answer == nil,
              !isSending else { return }
        q.answer = answer
        messages[idx].question = q

        let payload = "In response to your question \"\(q.question)\": \(answer.recap)"
        sendStarterMessage(payload)
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
        conversationGeneratedItemSets = []
        pendingInsights = []
        pendingOutfitItems = [:]
        pendingOutfitTags = [:]
        sourceOutfitIDForCopy = [:]
        pendingSeparatorMessageIDs = []
        errorMessage = nil
    }

    // MARK: - System Prompt
    //
    // The system prompt is split into two blocks so Anthropic's prompt cache can retain
    // the stable prefix across turns. The cached block is stable within a session (guidelines,
    // intent rules, mode behavior, comfort preferences, style mode). The fresh block holds
    // anything that may mutate during a conversation (weather, style summary, counts,
    // pending insights, behavioral observations).

    private func buildCachedSystemPrompt() -> String {
        var prompt = """
        You are the Attirely style agent — a warm, knowledgeable personal stylist who knows \
        this user's entire wardrobe. You help them decide what to wear, explore their style, \
        and discover new outfit combinations.

        GUIDELINES:
        - Be conversational and concise. Keep responses to 1-3 short paragraphs unless the user asks for detail.
        - NEVER list choices in prose. If your next sentence would be "Are you thinking: X, Y, or Z?" or "Would you prefer A or B?" — STOP and call askUserQuestion with those options instead. The UI renders them as tappable buttons. Example: instead of writing "What's the occasion? Smart casual, casual, or business casual?", call askUserQuestion with question="What's the occasion?" and options=["Smart casual", "Casual", "Business casual"]. After calling askUserQuestion, end your turn — do not emit more text; the user's answer will arrive next turn.
        - Never invent items the user doesn't own. If you're unsure, search first.
        - Reference items by their type and color (e.g. "your navy blazer") rather than IDs.
        - When the user explicitly states a style preference or dislike, use updateStyleInsight to record it. Do not announce that you're recording it — just acknowledge naturally.
        - When the user removes items from outfits, expresses dislike, or rejects suggestions, use updateStyleInsight to record the behavioral pattern as a negative signal. Include the category and signal fields when you can determine them.
        - If you notice recurring patterns in the user's choices across the conversation (e.g., they always pick dark colors, avoid certain fabrics), record these as low-confidence insights.

        INTENT DETECTION — choosing the right tool:
        - When the user wants something NEW, DIFFERENT, or a SURPRISE ("give me a new outfit", "surprise me", "something I haven't tried", "create an outfit for…"), use the generateOutfit tool. If you've already produced an outfit earlier in this conversation, vary the occasion, color palette, or anchor item on subsequent calls rather than repeating the same silhouette — the user expects a genuinely fresh combination each time.
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

        // Temperature display preference — avoid degree symbol to prevent UTF-8 encoding corruption
        let preferredUnit = userProfile?.temperatureUnit ?? .celsius
        let unitLabel = preferredUnit == .fahrenheit ? "Fahrenheit (F)" : "Celsius (C)"
        prompt += "\n\nTEMPERATURE DISPLAY: Weather data is provided in Celsius. When mentioning temperatures in your responses, convert and display in \(unitLabel)."

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

        return prompt
    }

    private func buildFreshSystemPrompt() -> String {
        var prompt = ""

        // Weather context
        if let weather = weatherViewModel?.weatherContextString {
            prompt += "CURRENT WEATHER:\n\(weather)"
        } else {
            prompt += "CURRENT WEATHER: Not available."
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
            immediately call generateOutfit. Instead, explore with searchWardrobe first; if a \
            preference is still needed (occasion, formality, vibe), call askUserQuestion with \
            button options — never ask in prose. EXCEPTION: if the user specifies a clear occasion \
            AND has no ambiguous preferences AND weather conditions are moderate, you may generate \
            directly.
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
