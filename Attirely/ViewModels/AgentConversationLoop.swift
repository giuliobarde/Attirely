import Foundation

// Surface the loop needs from the view model: prompt context, tool execution, and
// message-state mutations. Held weakly so the loop doesn't retain the VM.
@MainActor
protocol AgentLoopHost: AnyObject {
    func promptContext() -> AgentPromptContext
    func executeTool(_ call: ToolUseBlock) async -> (String, [Outfit], [ClothingItem], String?)
    func executeSuggestPurchases(_ input: SuggestPurchasesInput) async -> (String, [PurchaseSuggestionDTO])

    // Streaming message mutations
    func appendTextToStreamingMessage(streamingID: UUID, delta: String)
    func setToolStatus(streamingID: UUID, name: String)
    func clearToolStatus(streamingID: UUID)
    func setWarning(streamingID: UUID, text: String)
    func setRetryStatus(streamingID: UUID, text: String)
    func clearRetryStatus(streamingID: UUID)
    func finalizeStreamingMessage(streamingID: UUID)
    func finalizeMessage(streamingID: UUID, text: String?)
    func updateStreamingMessage(
        streamingID: UUID,
        text: String?,
        outfits: [Outfit],
        wardrobeItems: [ClothingItem],
        insightNote: String?,
        purchaseSuggestions: [PurchaseSuggestionDTO],
        question: AgentQuestion?
    )

    // Session-scoped state the loop touches
    func markPendingSeparator(streamingID: UUID)
    func didFinishSending()
}

// Orchestrates the tool-use loop over streamed SSE turns. Owns the API history and
// the retry/wrap-up state machine; delegates every user-visible mutation back to the host.
@MainActor
final class AgentConversationLoop {

    private weak var host: AgentLoopHost?

    // Hard cap on tool-use iterations. Raised from 5 so legitimate long tool chains
    // (e.g. suggestPurchases → searchWardrobe → generateOutfit → respond) don't get
    // cut off. The real guard is the repeat detector in the loop body.
    private static let maxLoops = 10
    private static let retryDelaysNs: [UInt64] = [1_000_000_000, 3_000_000_000, 7_000_000_000]
    private static let maxRetryAttempts = 3

    // API message history, preserved across turns within a conversation.
    private(set) var history: [[String: Any]] = []

    init(host: AgentLoopHost) {
        self.host = host
    }

    func reset() {
        history = []
    }

    func appendUserMessage(_ text: String) {
        history.append(["role": "user", "content": text])
    }

    func run(streamingID: UUID) async {
        guard let host else { return }

        let apiKey: String
        do {
            apiKey = try ConfigManager.apiKey()
        } catch {
            host.finalizeMessage(streamingID: streamingID, text: error.localizedDescription)
            host.didFinishSending()
            return
        }

        let cachedSystemPrompt = AgentPromptBuilder.buildCachedSystemPrompt(context: host.promptContext())

        do {
            var loopCount = 0
            var seenCallSignatures: Set<String> = []
            var wrapUpMode = false
            var completedNormally = false

            while loopCount < Self.maxLoops {
                guard !Task.isCancelled else { break }
                loopCount += 1

                host.clearToolStatus(streamingID: streamingID)

                let freshSystemPrompt = AgentPromptBuilder.buildFreshSystemPrompt(context: host.promptContext())
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

                let assistantContent = accumulator.rawAssistantContent()
                history.append(["role": "assistant", "content": assistantContent])

                let stopReason = accumulator.stopReason ?? "end_turn"
                let toolCalls = accumulator.finishedToolCalls()

                if stopReason != "tool_use" || wrapUpMode {
                    switch stopReason {
                    case "end_turn", "stop_sequence":
                        break
                    case "max_tokens":
                        host.setWarning(streamingID: streamingID, text: "Response was cut off (token limit).")
                    case "refusal":
                        host.setWarning(streamingID: streamingID, text: "Request declined.")
                    case "pause_turn":
                        host.setWarning(streamingID: streamingID, text: "Response paused.")
                    default:
                        break
                    }
                    host.finalizeStreamingMessage(streamingID: streamingID)
                    completedNormally = true
                    break
                }

                if toolCalls.isEmpty {
                    host.finalizeStreamingMessage(streamingID: streamingID)
                    completedNormally = true
                    break
                }

                var hadRepeat = false
                for call in toolCalls {
                    let sig = signatureFor(call)
                    if !seenCallSignatures.insert(sig).inserted {
                        hadRepeat = true
                        print("[AgentRunaway] Repeat call detected: \(call.name.rawValue) input=\(sig)")
                    }
                }

                var toolResultBlocks: [[String: Any]] = []
                var outfits: [Outfit] = []
                var foundItems: [ClothingItem] = []
                var insightNote: String?
                var purchaseSuggestions: [PurchaseSuggestionDTO] = []
                var pendingQuestion: AgentQuestion?

                for call in toolCalls {
                    if call.name == .suggestPurchases {
                        let (resultContent, suggestions) = await host.executeSuggestPurchases(
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
                        let (resultContent, toolOutfits, toolItems, toolInsight) = await host.executeTool(call)
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

                history.append(["role": "user", "content": toolResultBlocks])

                host.markPendingSeparator(streamingID: streamingID)

                if !outfits.isEmpty || !foundItems.isEmpty || insightNote != nil || !purchaseSuggestions.isEmpty || pendingQuestion != nil {
                    host.updateStreamingMessage(
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
                host.clearToolStatus(streamingID: streamingID)
                let freshSystemPrompt = AgentPromptBuilder.buildFreshSystemPrompt(context: host.promptContext())
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
                host.finalizeStreamingMessage(streamingID: streamingID)
            }
        } catch {
            if !Task.isCancelled {
                let errorText: String
                if case AnthropicError.overloaded = error {
                    errorText = "Claude is currently overloaded — please try again in a moment."
                } else {
                    errorText = "Something went wrong. Please try again."
                }
                host.finalizeMessage(streamingID: streamingID, text: errorText)
            }
        }

        host.didFinishSending()
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
        guard let host else { throw CancellationError() }
        var attempt = 0

        while true {
            attempt += 1
            host.clearRetryStatus(streamingID: streamingID)

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
                        host.appendTextToStreamingMessage(streamingID: streamingID, delta: text)
                    case .toolUseStart(_, _, let name):
                        host.setToolStatus(streamingID: streamingID, name: name)
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
                host.setRetryStatus(
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
}
