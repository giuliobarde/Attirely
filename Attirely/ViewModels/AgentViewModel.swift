import SwiftUI
import SwiftData

// Observable facade for Athena, the style agent. Owns UI-bound state and pending outfit data,
// and delegates the three heavy responsibilities to purpose-built collaborators:
// - AgentToolExecutor: tool routing + execution
// - AgentConversationLoop: SSE streaming + tool-use loop + history
// - AgentPromptBuilder / OutfitMatcher: pure helpers (called directly from collaborators)
//
// The VM holds observable state; collaborators hold the VM weakly via host protocols.
@Observable
class AgentViewModel {

    // MARK: - Agent Mode

    var effectiveMode: AgentMode = .conversational

    // MARK: - Conversation State

    var messages: [ChatMessage] = []
    var inputText = ""
    var isSending = false
    var errorMessage: String?

    // MARK: - Dependencies (set via .onAppear)

    var modelContext: ModelContext?
    var weatherViewModel: WeatherViewModel?
    var userProfile: UserProfile?
    var styleSummaryText: String?
    var styleViewModel: StyleViewModel?
    var styleSummary: StyleSummary?

    // MARK: - Wardrobe Snapshot (protocol-visible; set via refreshWardrobe)

    var wardrobeItems: [ClothingItem] = []
    var allOutfits: [Outfit] = []

    // MARK: - Pending Outfit Data (deferred until save to avoid SwiftData auto-persistence)

    var pendingOutfitItems: [UUID: [ClothingItem]] = [:]
    var pendingOutfitTags: [UUID: [Tag]] = [:]
    var sourceOutfitIDForCopy: [UUID: UUID] = [:]

    // Item-ID sets from outfits generated during the active chat session.
    var conversationGeneratedItemSets: [[String]] = []

    // MARK: - Pending Insights

    var pendingInsights: [(insight: String, confidence: String)] = []

    // MARK: - Task Management

    @ObservationIgnored private(set) var currentTask: Task<Void, Never>?

    // Message IDs whose next text delta should be preceded by a paragraph break.
    @ObservationIgnored private var pendingSeparatorMessageIDs: Set<UUID> = []

    // MARK: - Collaborators

    @ObservationIgnored private var executor: AgentToolExecutor!
    @ObservationIgnored private var loop: AgentConversationLoop!

    init() {
        self.executor = AgentToolExecutor(host: self)
        self.loop = AgentConversationLoop(host: self)
    }

    // MARK: - Public surface

    var hasUnsavedOutfits: Bool {
        !pendingOutfitItems.isEmpty
    }

    func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
        isSending = false
    }

    func displayItems(for outfit: Outfit) -> [ClothingItem] {
        pendingOutfitItems[outfit.id] ?? outfit.items
    }

    func isCopyOfSavedOutfit(_ outfit: Outfit) -> Bool {
        sourceOutfitIDForCopy[outfit.id] != nil
    }

    // MARK: - Refresh / Dependencies

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

        let userMessage = ChatMessage(role: .user, text: text)
        messages.append(userMessage)
        loop.appendUserMessage(text)

        let streamingID = UUID()
        messages.append(ChatMessage(id: streamingID, role: .assistant, isStreaming: true))

        currentTask = Task { [loop] in
            await loop?.run(streamingID: streamingID)
        }
    }

    func sendStarterMessage(_ text: String) {
        inputText = text
        sendUserMessage()
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

    // MARK: - Clear

    func clearConversation() {
        messages = []
        loop.reset()
        conversationGeneratedItemSets = []
        pendingInsights = []
        pendingOutfitItems = [:]
        pendingOutfitTags = [:]
        sourceOutfitIDForCopy = [:]
        pendingSeparatorMessageIDs = []
        errorMessage = nil
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

    // Called by both the executor (after mutating a saved outfit) and saveOutfit.
    func notifyStyleAnalysis() {
        guard let context = modelContext else { return }
        let items = (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? []
        let outfits = (try? context.fetch(FetchDescriptor<Outfit>())) ?? []
        styleViewModel?.analyzeStyle(items: items, outfits: outfits, profile: userProfile)
    }

    // Exposed for executor/loop via the host protocols.
    func saveIfPossible() {
        try? modelContext?.save()
    }

    // Drops pending entries whose outfit is no longer referenced by any chat message.
    // Called at the end of each turn so abandoned outfits (e.g. ones replaced via
    // updateOriginalFromCopy or edits that never landed in messages) don't accumulate.
    func pruneOrphanedPendingOutfits() {
        let liveIDs: Set<UUID> = Set(messages.flatMap { $0.outfits.map(\.id) })

        let beforeItems = pendingOutfitItems.count
        pendingOutfitItems = pendingOutfitItems.filter { liveIDs.contains($0.key) }
        pendingOutfitTags = pendingOutfitTags.filter { liveIDs.contains($0.key) }
        sourceOutfitIDForCopy = sourceOutfitIDForCopy.filter { liveIDs.contains($0.key) }

        let dropped = beforeItems - pendingOutfitItems.count
        if dropped > 0 {
            AgentTelemetry.recordPrunedPendingOutfits(dropped)
        }
    }

    func updateOriginalFromCopy(_ copy: Outfit) {
        executor.updateOriginalFromCopy(copy)
    }

    // MARK: - Tool phrase mapping (for status line)

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
}

// MARK: - AgentToolHost

extension AgentViewModel: AgentToolHost {

    func refreshMessageContaining(outfitID: UUID) {
        guard let msgIndex = messages.firstIndex(where: { $0.outfits.contains(where: { $0.id == outfitID }) }) else { return }
        var msg = messages[msgIndex]
        msg.outfits = msg.outfits.map { $0 }
        messages[msgIndex] = msg
    }

    func replaceOutfit(fromMessageContaining copyID: UUID, removing removeID: UUID) {
        guard let msgIndex = messages.firstIndex(where: { $0.outfits.contains(where: { $0.id == copyID }) }) else { return }
        var msg = messages[msgIndex]
        msg.outfits.removeAll { $0.id == removeID }
        messages[msgIndex] = msg
    }
}

// MARK: - AgentLoopHost

extension AgentViewModel: AgentLoopHost {

    func promptContext() -> AgentPromptContext {
        AgentPromptContext(
            mode: effectiveMode,
            userProfile: userProfile,
            wardrobeItems: wardrobeItems,
            allOutfits: allOutfits,
            styleSummary: styleSummary,
            styleSummaryText: styleSummaryText,
            weatherContextString: weatherViewModel?.weatherContextString,
            pendingInsights: pendingInsights
        )
    }

    func executeTool(_ call: ToolUseBlock) async -> (String, [Outfit], [ClothingItem], String?) {
        await executor.execute(call)
    }

    func executeSuggestPurchases(_ input: SuggestPurchasesInput) async -> (String, [PurchaseSuggestionDTO]) {
        await executor.executeSuggestPurchases(input)
    }

    func appendTextToStreamingMessage(streamingID: UUID, delta: String) {
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
            messages[index].isStreaming = false
            messages[index].toolStatus = nil
            messages[index].retryStatus = nil
        } else {
            messages[index].text?.append(effectiveDelta)
        }
    }

    func setToolStatus(streamingID: UUID, name: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].toolStatus = phraseForTool(name)
    }

    func clearToolStatus(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].toolStatus = nil
    }

    func setWarning(streamingID: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].warning = text
    }

    func setRetryStatus(streamingID: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].retryStatus = text
    }

    func clearRetryStatus(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].retryStatus = nil
    }

    func finalizeStreamingMessage(streamingID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].isStreaming = false
        messages[index].toolStatus = nil
        messages[index].retryStatus = nil
    }

    func finalizeMessage(streamingID: UUID, text: String?) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        messages[index].text = text
        messages[index].isStreaming = false
    }

    func updateStreamingMessage(
        streamingID: UUID,
        text: String?,
        outfits: [Outfit],
        wardrobeItems: [ClothingItem],
        insightNote: String?,
        purchaseSuggestions: [PurchaseSuggestionDTO],
        question: AgentQuestion?
    ) {
        guard let index = messages.firstIndex(where: { $0.id == streamingID }) else { return }
        if let text { messages[index].text = text }
        messages[index].outfits.append(contentsOf: outfits)
        messages[index].wardrobeItems.append(contentsOf: wardrobeItems)
        if let insightNote { messages[index].insightNote = insightNote }
        messages[index].purchaseSuggestions.append(contentsOf: purchaseSuggestions)
        if let question { messages[index].question = question }
    }

    func markPendingSeparator(streamingID: UUID) {
        pendingSeparatorMessageIDs.insert(streamingID)
    }

    func didFinishSending() {
        isSending = false
    }
}
