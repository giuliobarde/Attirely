# Agent Improvement Plan

Scope: the Attirely style agent — chat loop, tool calls, streaming, and learning system.
Files touched: [AgentViewModel.swift](Attirely/ViewModels/AgentViewModel.swift), [AgentService.swift](Attirely/Services/AgentService.swift), [AgentMessageBubble.swift](Attirely/Views/AgentMessageBubble.swift), [AgentView.swift](Attirely/Views/AgentView.swift), [SSETypes.swift](Attirely/Models/SSETypes.swift), [AgentToolDTO.swift](Attirely/Models/AgentToolDTO.swift).

---

## What's working well

- Tool surface is focused: 7 well-scoped tools with clear intent-detection rules.
- SSE streaming with cooperative `Task` cancellation via `currentTask`.
- Pending-state pattern (`pendingOutfitItems`, `pendingOutfitTags`) cleanly defers SwiftData inserts until "Save".
- Edit-as-proposal flow preserves saved outfits — good UX.
- Conversation dedup (`conversationGeneratedItemSets`) prevents repeat suggestions in one chat.
- Learning loop via `ObservationManager` with Jaccard fuzzy matching and threshold-based confidence.

---

## Priority 1 — ship first (highest ROI)

### 1.1 Add prompt caching
- **Problem**: the full system prompt (guidelines + intent detection + mode block + weather + style summary + observations + wardrobe counts) is re-tokenized every turn. Tool definitions are ~3 KB of stable text re-sent on every call.
- **Change**: in [AgentService.swift:54-70](Attirely/Services/AgentService.swift#L54-L70), switch `system` from a string to a structured block and add `cache_control: {"type": "ephemeral"}` on the static portion (guidelines, intent detection, tool definitions). Keep dynamic fragments (weather, wardrobe counts) outside the cache.
- **Impact**: 50–80% latency drop on follow-up turns; proportional cost drop.

### 1.2 raise token budget
- **Problem**: [AgentService.swift:5](Attirely/Services/AgentService.swift#L5) pins `claude-sonnet-4-20250514`; `maxTokens = 2048` is tight for chained tool turns.
- **Change**: Bump `maxTokens` to 4096.
- **Impact**: better tool-use reliability, fewer truncated responses.

### 1.3 Handle `stop_reason` properly
- **Problem**: [AgentViewModel.swift:193](Attirely/ViewModels/AgentViewModel.swift#L193) only distinguishes `end_turn` from "has tool calls". `max_tokens`, `refusal`, `pause_turn` all fall through silently — truncated responses look like completed ones.
- **Change**: switch on all `stop_reason` values. On `max_tokens`, either continue with a follow-up turn or show a warning.

---

## Priority 2 — UX polish

### 2.1 Stream tool-use status to the UI
- **Problem**: `isStreaming` flips false on first text delta ([AgentMessageBubble.swift:57](Attirely/Views/AgentMessageBubble.swift#L57)). When the model goes straight to a tool without preamble, users stare at thinking dots.
- **Change**: in `ContentBlockAccumulator.apply` for `.toolUseStart`, emit a status update ("Searching your wardrobe…", "Building an outfit…") based on tool name. Surface it on `ChatMessage`.

### 2.2 Retry transient errors with backoff
- **Problem**: [AgentViewModel.swift:268](Attirely/ViewModels/AgentViewModel.swift#L268) shows "Claude overloaded" as a dead-end.
- **Change**: exponential backoff (1s, 3s, 7s) with a visible "retrying…" state in the bubble. Max 3 attempts.

### 2.3 Replace `maxLoops = 5` with a runaway guard + wrap-up turn
- **Problem**: [AgentViewModel.swift:154](Attirely/ViewModels/AgentViewModel.swift#L154) silently stops at 5 iterations. A flat iteration cap conflates two different failures: a legitimate long tool chain (e.g. `suggestPurchases` → `searchWardrobe` → `generateOutfit` → respond) and a true runaway (model calling the same tool with the same input over and over). Punishing the former to catch the latter is the wrong shape.
- **Change**:
  1. Raise the hard cap from 5 → 10 as a last-resort safety net (never expected to hit).
  2. Add the real runaway guard: track `(toolName, normalized(inputJSON))` tuples within a single conversation loop. If the same call repeats, break immediately.
  3. On either trigger, make **one final API call with `tools: []`** so the model produces a clean text wrap-up. No fake tool_result, no history pollution — an empty tools list is a legitimate API shape.
  4. Log every trigger with tool name + normalized input so repeat bugs are debuggable.
- **Why not the synthetic tool_result approach**: it lies to the model, pollutes history (hurting prompt-cache hit rate on subsequent turns), and still doesn't distinguish "legit long chain" from "buggy infinite loop".

---

## Priority 3 — structural debt

### 3.1 Split `AgentViewModel` (1119 lines)
CLAUDE.md rules out view models beyond ~200 lines. Extract:
- `AgentConversationLoop` — SSE loop + history management (lines 140–278)
- `AgentToolExecutor` — the six `executeX` functions (lines 282–734)
- `AgentPromptBuilder` — `buildSystemPrompt`, `modeBehaviorBlock`, `ambiguousIntentRule` (lines 963–1117)
- `OutfitMatcher` — `matchItem`, `normalizeMatchWords`, `normalizeToken` (lines 808–853)

The view model should only own observable state and delegate.

### 3.2 Address item-matching correctness risk
- **Problem**: [matchItem](Attirely/ViewModels/AgentViewModel.swift#L808-L833) uses fuzzy word overlap. No UUIDs are exposed to the agent. Two navy blazers → `max(by: score)` picks arbitrarily.
- **Change**:
  1. Expose short deterministic IDs to the agent in tool results (e.g. `[a3f]` prefix) and parse them back (scaffolding already at [line 811](Attirely/ViewModels/AgentViewModel.swift#L811)).
  2. Return matches as structured JSON in `tool_result.content` instead of prose, so the model reasons over typed data.

### 3.3 History compaction
- **Problem**: `history` in [AgentViewModel.swift:20](Attirely/ViewModels/AgentViewModel.swift#L20) grows unbounded. 15 turns with tool calls = 40+ blocks.
- **Change**: rolling window — keep last N turns verbatim, summarize older turns into a single "Earlier in this conversation: …" message. Or drop stale tool_result *content* (keep IDs for structural validity).

### 3.4 Parallelize independent tool calls
- **Problem**: [AgentViewModel.swift:206](Attirely/ViewModels/AgentViewModel.swift#L206) executes tools sequentially even when they're independent.
- **Change**: `withTaskGroup` for non-mutating tools (`searchWardrobe`, `searchOutfits`, `suggestPurchases`). Keep `editOutfit` and `updateStyleInsight` sequential.

---

## Priority 4 — polish

- `AgentQuestion` is single-shot per message ([line 900](Attirely/ViewModels/AgentViewModel.swift#L900)) — a second `askUserQuestion` silently overwrites the first. Reject the second or model as `[AgentQuestion]`.
- Tool-result strings contain rendering instructions ("Display these…", "Do not say the edit failed…", [line 665](Attirely/ViewModels/AgentViewModel.swift#L665)). Move to system prompt; keep tool results factual.
- `pendingOutfitItems` never purges for abandoned (never-saved) outfits still held by `messages` — slow memory growth in long chats.
- No telemetry: can't measure tool-call distribution, hallucinated-ID rate, avg round-trip. Add a lightweight counter in `AgentToolExecutor`.
- Tool-use JSON parse failure at [SSETypes.swift:68](Attirely/Models/SSETypes.swift#L68) silently becomes `{}` — at minimum, log the malformed JSON.
- Intent-detection rules are duplicated across system prompt *and* tool descriptions. Consolidate.

---

## Suggested sequencing

| Week | Items | Goal |
|------|-------|------|
| 1 | 1.1, 1.2, 1.3 | Immediate latency / cost / quality wins |
| 2 | 2.1, 2.2, 2.3 | User-facing polish |
| 3–4 | 3.1, 3.2, 3.3, 3.4 | Structural debt + correctness |
| 5+ | Priority 4 | Quality-of-life cleanup |

---

## Success metrics

- **Latency**: p50 time-to-first-token on follow-up turns (target: −50% after 1.1).
- **Cost**: tokens per conversation (target: −40% after 1.1).
- **Correctness**: % of `must_include_items` that resolve to the intended item (target: >95% after 3.2).
- **Reliability**: % of turns hitting `max_tokens` or `maxLoops` (target: <1%).
- **Engagement**: % of generated outfits saved (baseline before changes, re-measure after).
