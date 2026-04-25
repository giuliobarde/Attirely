# Agent Improvement Plan — Pantheon Integration

Scope: refactor the Attirely style agent so it can run behind The Pantheon's `InferenceProvider` abstraction. The agent should work identically whether backed by the Claude API (current) or by a local model via Olympus/Athena routing.

**Goal:** when The Pantheon's Athena agent receives a style request, it delegates to the same tool-execution and prompt-building logic that Attirely uses today — but the inference call goes through the Pantheon's provider, not directly to Anthropic.

---

## Current Anthropic coupling points

| Layer | File(s) | What's coupled | Severity |
|-------|---------|---------------|----------|
| Transport | `AnthropicService.swift` | Hard-coded URL, headers, model ID, Anthropic JSON body shape | High |
| Request builder | `AgentService.swift` | `cache_control: ephemeral`, Anthropic system block format, tool schema shape | High |
| SSE parsing | `SSEStreamParser.swift`, `SSETypes.swift` | Anthropic-specific event types (`content_block_start`, `content_block_delta`, `input_json_delta`) | High |
| Conversation history | `AgentConversationLoop.swift` | History stored as literal Anthropic `messages` payload (`[[String: Any]]`), `tool_result` with `tool_use_id` pairing | High |
| Tool block parsing | `AgentToolDTO.swift` | `ToolUseBlock` expects Anthropic's `id`/`name`/`input` shape | Medium |
| Stop reasons | `AgentConversationLoop.swift` | Switches on `end_turn`, `tool_use`, `max_tokens` — Anthropic-specific strings | Medium |
| Error handling | `AgentConversationLoop.swift`, `AgentToolExecutor.swift` | Catches `AnthropicError` for retry logic and nested generation | Medium |
| Prompt builder | `AgentPromptBuilder.swift` | Content is generic, but assumes two-block split for Anthropic cache | Low |
| Tool executor | `AgentToolExecutor.swift` | Domain tools are generic; nested calls to `AnthropicService.generateOutfits`/`suggestPurchases` are coupled | Medium |
| View model | `AgentViewModel.swift` | Provider-agnostic — talks only to protocols | None |

---

## Priority 1 — Inference abstraction layer

### 1.1 Define `InferenceProvider` protocol

Create a provider-agnostic interface that both the Anthropic API and future Pantheon/Ollama backends can conform to.

```swift
protocol InferenceProvider {
    var modelId: String { get }

    func complete(
        system: [SystemBlock],
        messages: [ConversationMessage],
        tools: [ToolDefinition]?,
        maxTokens: Int
    ) async throws -> InferenceResult

    func stream(
        system: [SystemBlock],
        messages: [ConversationMessage],
        tools: [ToolDefinition]?,
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamChunk, Error>
}
```

**Files:** new `Services/InferenceProvider.swift`

### 1.2 Define normalized domain types

Replace raw `[String: Any]` dictionaries with typed models that are provider-agnostic:

- `ConversationMessage` — role + content blocks (text, tool_use, tool_result, image)
- `ToolUseCall` — id, name, input (replaces `ToolUseBlock`'s Anthropic-specific init)
- `ToolResultBlock` — tool_use_id, content string
- `InferenceResult` — text, tool calls, stop reason enum
- `StreamChunk` — normalized streaming event (text delta, tool call start, tool input delta, done)
- `StopReason` — `.endTurn`, `.toolUse`, `.maxTokens` (provider maps its native strings to this)
- `SystemBlock` — text + optional cache hint (providers that don't support caching ignore it)
- `InferenceError` — `.rateLimited`, `.overloaded`, `.invalidRequest`, `.networkError` (with `isRetryable`)

**Files:** new `Models/InferenceTypes.swift`

### 1.3 Create `AnthropicInferenceAdapter`

Wrap the current `AnthropicService` agent methods + `SSEStreamParser` behind `InferenceProvider`:

- Maps `ConversationMessage` → Anthropic JSON body
- Maps `SystemBlock` → Anthropic system array with `cache_control`
- Maps `ToolDefinition` → Anthropic tool schema JSON
- Parses Anthropic SSE events → `StreamChunk`
- Maps Anthropic stop reasons → `StopReason` enum
- Maps `AnthropicError` → `InferenceError`

This is a **wrap, not rewrite**. The existing `AnthropicService` streaming and parsing code moves inside the adapter largely unchanged.

**Files:** new `Services/AnthropicInferenceAdapter.swift`, modified `AgentService.swift`

### 1.4 Create `PantheonInferenceAdapter` (stub)

A stub adapter that will eventually call The Pantheon's local endpoint instead of the Anthropic API. For now it conforms to `InferenceProvider` and throws "not configured." This validates the abstraction compiles and the protocol is complete.

When The Pantheon is ready, this adapter will:
- POST to the Mac's local Ollama/inference endpoint
- Parse Ollama-format streaming responses → `StreamChunk`
- Map Ollama tool call format → `ToolUseCall`
- Handle the simpler system prompt format (single string, no cache blocks)

**Files:** new `Services/PantheonInferenceAdapter.swift`

---

## Priority 2 — Decouple the conversation loop

### 2.1 Replace `[[String: Any]]` history with typed `[ConversationMessage]`

`AgentConversationLoop.history` currently stores raw Anthropic JSON. Replace with `[ConversationMessage]` from Priority 1.2. Each adapter serializes the typed history into its provider's wire format when building the request.

**Impact:** history compaction, tool-result elision, and message appending all operate on typed data instead of dictionary surgery.

**Files:** `AgentConversationLoop.swift`

### 2.2 Replace `ContentBlockAccumulator` with provider-agnostic stream assembly

`ContentBlockAccumulator` and `SSETypes` are tightly coupled to Anthropic's streaming protocol. Replace with a `StreamAssembler` that consumes `StreamChunk` (from the provider) and produces a `ConversationMessage` (assistant turn with text + tool calls).

Each provider's adapter handles its own raw stream parsing. The loop only sees normalized chunks.

**Files:** `AgentConversationLoop.swift`, `SSETypes.swift` (possibly retired or reduced)

### 2.3 Generalize stop-reason handling

Replace string comparisons (`"end_turn"`, `"tool_use"`) with switches on the `StopReason` enum from 1.2.

**Files:** `AgentConversationLoop.swift`

### 2.4 Generalize retry logic

Replace `AnthropicError` catches with `InferenceError` from 1.2. The `isRetryable` property moves to the error enum.

**Files:** `AgentConversationLoop.swift`

---

## Priority 3 — Decouple nested generation calls

### 3.1 Define `GenerationService` protocol

`AgentToolExecutor` currently calls `AnthropicService.generateOutfits()` and `AnthropicService.suggestPurchases()` directly — these are full second API round-trips baked into tool execution. Extract a protocol:

```swift
protocol GenerationService {
    func generateOutfits(items: [ClothingItem], ...) async throws -> [OutfitDTO]
    func suggestPurchases(items: [ClothingItem], ...) async throws -> [PurchaseSuggestionDTO]
}
```

The current `AnthropicService` static methods back this initially. When running through The Pantheon, Athena could handle generation directly (eliminating the nested call) or route to the same local model with a different prompt.

**Files:** new `Services/GenerationService.swift`, modified `AgentToolExecutor.swift`

### 3.2 Inject provider into `AgentToolExecutor`

The executor currently has no provider dependency — it calls `AnthropicService` statics. Inject the `GenerationService` at init so the provider is swappable.

**Files:** `AgentToolExecutor.swift`, `AgentViewModel.swift` (passes dependency at init)

---

## Priority 4 — Pantheon communication endpoint

### 4.1 Expose agent capabilities as a local API

When The Pantheon's Athena routes a request to Attirely, the app needs to receive it. Add a lightweight local HTTP endpoint (or use Bonjour + MultipeerConnectivity) that:

- Accepts incoming style/wardrobe requests from The Pantheon
- Routes them through the same `AgentConversationLoop` + `AgentToolExecutor` pipeline
- Returns results back to The Pantheon
- Only responds to the developer's account (checked via device ID or local-only binding)

This is the bridge described in The Pantheon's SPEC.md under "Relationship to Attirely."

**Files:** new `Services/PantheonBridge.swift` (or similar)

### 4.2 Share style profile with The Pantheon

The Pantheon's Athena needs access to the user's `StyleSummary`, behavioral observations, and wardrobe data. Define a data export format that The Pantheon can ingest:

- Wardrobe items (attributes, tags, images)
- Style profile (StyleSummary, observations)
- Outfit history (saved, dismissed)
- Occasion preferences

This could be a simple JSON export endpoint on the local API from 4.1, or a shared data store if both systems run on the same Mac.

**Files:** TBD based on Pantheon architecture decisions

---

## What stays unchanged

- **`AgentViewModel.swift`** — already provider-agnostic. No changes needed.
- **`AgentPromptBuilder.swift`** — content is generic. Providers decide how to use the cached/fresh split.
- **Tool execution logic** — `searchWardrobe`, `editOutfit`, `searchOutfits`, etc. are pure domain logic operating on SwiftData. Provider-independent.
- **`OutfitMatcher.swift`** — alias resolution, fuzzy matching. Provider-independent.
- **UI layer** — `AgentView`, `AgentMessageBubble`, etc. See state from the view model only.

---

## Suggested sequencing

| Phase | Items | Goal |
|-------|-------|------|
| 1 | 1.1, 1.2, 1.3, 1.4 | InferenceProvider protocol + Anthropic adapter + Pantheon stub. Agent works identically but through the abstraction. |
| 2 | 2.1, 2.2, 2.3, 2.4 | Conversation loop decoupled from Anthropic wire format. History is typed. |
| 3 | 3.1, 3.2 | Nested generation calls decoupled. Tool executor is fully provider-agnostic. |
| 4 | 4.1, 4.2 | Local API endpoint for Pantheon communication. Style data sharing. |

Phases 1-3 can proceed independently of The Pantheon's development. Phase 4 depends on Pantheon architecture decisions (open questions in SPEC.md).

---

## Success criteria

- **Zero behavior change** after phases 1-3: the agent works exactly as before through the Anthropic adapter.
- **Compilation test:** `PantheonInferenceAdapter` stub compiles and conforms to `InferenceProvider` — validates the abstraction is complete.
- **No `AnthropicService` imports** outside of `AnthropicInferenceAdapter` and the non-agent vision/scan methods (those stay Anthropic-specific until The Pantheon handles vision).
- **No `[String: Any]`** in `AgentConversationLoop` — all history is typed.
- **Swappable at init:** changing one config flag routes all agent inference through a different provider.
