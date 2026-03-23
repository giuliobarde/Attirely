import SwiftUI
import SwiftData

@Observable
class AgentViewModel {

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

    // MARK: - Wardrobe Snapshot

    private var wardrobeItems: [ClothingItem] = []
    private var allOutfits: [Outfit] = []

    // MARK: - Pending Insights

    private var pendingInsights: [(insight: String, confidence: String)] = []

    // MARK: - Refresh

    func refreshWardrobe(items: [ClothingItem], outfits: [Outfit]) {
        wardrobeItems = items
        allOutfits = outfits
    }

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

        Task {
            await runConversationLoop(streamingID: streamingID)
        }
    }

    func sendStarterMessage(_ text: String) {
        inputText = text
        sendUserMessage()
    }

    // MARK: - Conversation Loop

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
                loopCount += 1

                let turn = try await AgentService.sendMessage(
                    history: history,
                    systemPrompt: systemPrompt,
                    tools: AgentService.toolDefinitions,
                    apiKey: apiKey
                )

                // Append assistant content to history
                history.append(["role": "assistant", "content": turn.rawAssistantContent])

                if turn.stopReason == "end_turn" || turn.toolCalls.isEmpty {
                    finalizeMessage(streamingID: streamingID, text: turn.assistantText)
                    break
                }

                // Execute tools and collect results
                var toolResultBlocks: [[String: Any]] = []
                var outfits: [Outfit] = []
                var foundItems: [ClothingItem] = []
                var insightNote: String?

                for call in turn.toolCalls {
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

                // Append tool results as user message in history
                history.append(["role": "user", "content": toolResultBlocks])

                // Update streaming message with intermediate results
                if !outfits.isEmpty || !foundItems.isEmpty || insightNote != nil {
                    updateStreamingMessage(
                        streamingID: streamingID,
                        text: turn.assistantText,
                        outfits: outfits,
                        wardrobeItems: foundItems,
                        insightNote: insightNote
                    )
                }
            }
        } catch {
            let errorText = "Something went wrong: \(error.localizedDescription)"
            finalizeMessage(streamingID: streamingID, text: errorText)
        }

        isSending = false
    }

    // MARK: - Tool Execution

    private func executeTool(_ call: ToolUseBlock) async -> (String, [Outfit], [ClothingItem], String?) {
        switch call.name {
        case .generateOutfit:
            return await executeGenerateOutfit(GenerateOutfitInput(from: call.inputJSON))
        case .searchWardrobe:
            return executeSearchWardrobe(SearchWardrobeInput(from: call.inputJSON))
        case .updateStyleInsight:
            return executeUpdateStyleInsight(UpdateStyleInsightInput(from: call.inputJSON))
        }
    }

    private func executeGenerateOutfit(_ input: GenerateOutfitInput) async -> (String, [Outfit], [ClothingItem], String?) {
        guard wardrobeItems.count >= 2 else {
            return ("The user's wardrobe has fewer than 2 items. They need to add more items before generating outfits.", [], [], nil)
        }

        do {
            let apiKey = try ConfigManager.apiKey()
            _ = apiKey // used by AnthropicService internally

            let existingItemSets = allOutfits.map { outfit in
                outfit.items.map { $0.id.uuidString }.sorted()
            }

            let suggestions = try await AnthropicService.generateOutfits(
                from: wardrobeItems,
                occasion: input.occasion,
                season: weatherViewModel?.suggestedSeason,
                weatherContext: weatherViewModel?.weatherContextString,
                comfortPreferences: comfortPreferencesString(),
                styleSummary: styleSummaryText,
                existingOutfitItemSets: existingItemSets
            )

            var createdOutfits: [Outfit] = []
            for suggestion in suggestions {
                let matchedItems = wardrobeItems.filter {
                    suggestion.itemIDs.contains($0.id.uuidString)
                }
                let minRequired = min(3, suggestion.itemIDs.count)
                guard matchedItems.count >= minRequired else { continue }

                let outfit = Outfit(
                    name: suggestion.name,
                    occasion: suggestion.occasion,
                    reasoning: suggestion.reasoning,
                    isAIGenerated: true,
                    items: matchedItems
                )
                createdOutfits.append(outfit)
            }

            if createdOutfits.isEmpty {
                return ("Could not generate a valid outfit from the wardrobe. Some suggested items could not be matched.", [], [], nil)
            }

            let outfit = createdOutfits[0]
            let itemSummary = outfit.items.map { "\($0.type) (\($0.primaryColor))" }.joined(separator: ", ")
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

    private func executeSearchWardrobe(_ input: SearchWardrobeInput) -> (String, [Outfit], [ClothingItem], String?) {
        let query = input.query.lowercased()
        let words = query.split(separator: " ").map { String($0) }

        let matches = wardrobeItems.filter { item in
            let searchableText = [
                item.type, item.category, item.primaryColor,
                item.secondaryColor ?? "", item.pattern,
                item.fabricEstimate, item.formality,
                item.itemDescription, item.brand ?? "",
                item.season.joined(separator: " ")
            ].joined(separator: " ").lowercased()

            return words.allSatisfy { searchableText.contains($0) }
        }

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
        styleViewModel?.appendAgentInsight(input.insight)
        return ("Insight recorded.", [], [], input.insight)
    }

    // MARK: - Message Management

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
        insightNote: String?
    ) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        if let text { messages[index].text = text }
        messages[index].outfits.append(contentsOf: outfits)
        messages[index].wardrobeItems.append(contentsOf: wardrobeItems)
        if let insightNote { messages[index].insightNote = insightNote }
    }

    // MARK: - Save Outfit

    func saveOutfit(_ outfit: Outfit) {
        guard let modelContext else { return }
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
        - When the user asks what to wear or wants outfit suggestions, ALWAYS use the generateOutfit tool — never describe outfits from memory or guess item names.
        - When the user asks about specific items they own, use the searchWardrobe tool to get accurate results.
        - When the user explicitly states a style preference or dislike, use updateStyleInsight to record it. Do not announce that you're recording it — just acknowledge naturally.
        - Never invent items the user doesn't own. If you're unsure, search first.
        - Reference items by their type and color (e.g. "your navy blazer") rather than IDs.
        """

        // Weather context
        if let weather = weatherViewModel?.weatherContextString {
            prompt += "\n\nCURRENT WEATHER:\n\(weather)"
        } else {
            prompt += "\n\nCURRENT WEATHER: Not available."
        }

        // Comfort preferences
        if let comfort = comfortPreferencesString() {
            prompt += "\n\nUSER COMFORT PREFERENCES:\n\(comfort)"
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

        // Pending insights from this session
        if !pendingInsights.isEmpty {
            prompt += "\n\nINSIGHTS CAPTURED THIS SESSION:"
            for insight in pendingInsights {
                prompt += "\n- \(insight.insight)"
            }
        }

        return prompt
    }

    private func comfortPreferencesString() -> String? {
        guard let profile = userProfile else { return nil }
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
