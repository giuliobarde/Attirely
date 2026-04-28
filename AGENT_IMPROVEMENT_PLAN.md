# Athena Agent — Improvement Plan

A deep-read of the current agent implementation (v0.10.7) plus concrete suggestions for where it can be sharper, faster, smarter, and friendlier. Items are loosely ordered by impact-to-effort. Some are ideas worth a brainstorm; others are near-trivial code edits. There is no "everything is broken" — the implementation is already in a good place. This is a polish-and-extend list, not a rewrite plan.

---

## 1. Performance & Latency

### 1.1 Pin the model and consider tier mixing
`AgentService.model` is hardcoded to `claude-sonnet-4-20250514`. Two things to look at:

- **Bump to the current Sonnet generation.** The constant has been stable since the project moved to Sonnet 4 last spring. Sonnet 4.6 is the current frontier mid-tier and is materially faster on agentic tool-use loops.
- **Tier the routing.** A lot of the agent's work is mechanical: deciding *which tool to call* on a clear request ("show me my blazers", "what should I wear today"). That kind of intent-routing is well within Haiku 4.5's reach and roughly 3× faster / cheaper. A cheap-but-realistic split:
  - First turn (intent detection + first tool call) → Haiku 4.5
  - Tool-result synthesis and conversational response → Sonnet 4.6
  
  This is non-trivial because the conversation history has to flow between models, but Anthropic's prompt caching survives the model switch as long as the cached blocks are byte-identical. Worth prototyping behind a feature flag before committing.

### 1.2 Move the wardrobe alias index into the cached system block
`AgentPromptBuilder.wardrobeBlock` currently lives in `buildFreshSystemPrompt` and is rebuilt every turn. For wardrobes ≤ 40 items this can be 800–1,500 tokens of stable text that pays full input price every turn. The wardrobe rarely changes mid-conversation — the right place for this block is the cached prefix.

Concrete change:
- Move the wardrobe overview + alias index into `buildCachedSystemPrompt`.
- Keep weather, style summary, and pending insights in the fresh suffix.
- If the wardrobe changes mid-session (rare — user adds an item via Scan), the cache will invalidate that turn and rebuild. That's fine.

This is the single highest-leverage perf change in the file. Expect a real reduction in input tokens per turn on every conversation past the first reply.

### 1.3 Cache the tool definitions
`AgentService.toolDefinitions` is a stable ~3 KB object. Anthropic's prompt cache supports caching `tools` along with the system block when there's a `cache_control` breakpoint on the cached block (already in place). Confirm by inspecting `cache_creation_input_tokens` vs `cache_read_input_tokens` on a multi-turn session — the second turn should report ~0 creation tokens.

If tools are not currently being cached, the fix is to ensure the order is `system (with cache_control) → tools → messages` and that `tools` is identical byte-for-byte across turns (it is).

### 1.4 Add a second cache breakpoint on the conversation history
Anthropic supports up to 4 cache_control breakpoints. Right now we use one (system). On long conversations the history itself can be cached up to a recent boundary, e.g. the last user message. Strategy:

- Place a `cache_control: ephemeral` block on the second-to-last user turn each time we append a new user message.
- This means each turn pays cache-write on roughly the last exchange and cache-read on everything before it.
- Compaction (the existing `compactHistoryIfNeeded`) already keeps the older history byte-stable, so the cache will persist across turns.

### 1.5 Stop rebuilding `freshSystemPrompt` on the wrap-up turn
In `AgentConversationLoop.run`, the wrap-up turn rebuilds the full fresh system prompt only to pass `tools: []`. Reuse the last `freshSystemPrompt` from the loop variable — it's identical and cheaper.

### 1.6 The `searchWardrobe` result has no cap
Today it returns *every* matching item, with full alias + type + category + color + formality + description per row. For a 200-item wardrobe and a vague query ("blue", "tops") this can dump a few KB into the tool result. Cap at the top 30 matches, sorted by score (already computed), and append a tail line like "…and N more — refine the query for the rest." This shrinks tool_result tokens and gives the agent a clearer signal about what to pass on to `generateOutfit`.

### 1.7 Move `Dictionary(grouping:)` and similar work off the hot path
Minor: `RelevanceScorer.selectCandidates` runs every `generateOutfit` call. The wardrobe snapshot in `AgentViewModel` only changes on add/remove (already debounced via `onChange(of: count)`). A simple memoized `relevanceContext` per wardrobe-version would avoid recomputing scores when the same conversation calls `generateOutfit` twice. Worth measuring before optimizing — likely small.

---

## 2. Conversation Robustness

### 2.1 Persist conversations across app launches
Currently `ChatMessage` and the API `history` are entirely in-memory. Tab-switching is fine because `AgentView` lifecycle keeps `viewModel` alive, but on app kill / iOS memory eviction the user loses an in-progress conversation including any pending unsaved outfits. Two options:

- **Light:** Persist the most recent conversation to disk (JSON file under `Application Support/`) on every assistant message finalize. Restore on launch. Throw away on `clearConversation`. Simple, no SwiftData migration.
- **Heavy:** Add a SwiftData `Conversation` model with messages and pending outfits. Enables history of past chats ("yesterday I asked about a wedding outfit"). Bigger, but unlocks future Athena-as-journal features.

Recommend the light path first.

### 2.2 Wardrobe snapshot misses content edits
`AgentView` re-snapshots the wardrobe with `onChange(of: wardrobeItems.count)` and `allOutfits.count`. If the user edits an item's primary color, formality, or type from `ItemDetailView` while a chat is open in another tab, the agent will keep using stale attributes. Use a content-aware trigger: track the most-recent `updatedAt` on the wardrobe (or a hash of `id|updatedAt` pairs) and refresh when it shifts.

### 2.3 Repeat detector lifetime is too long
`seenCallSignatures` lives for the whole user-message loop. Legitimate sequences like:

> User: "What do I have in red?" → searchWardrobe(red)
> User (next turn): "And in blue?" → searchWardrobe(blue) → fine
> User (turn after): "Now red again, but only formal" → searchWardrobe(red formal)

…are fine because inputs differ. But if the model legitimately needs to re-call `searchWardrobe(red)` on a later turn (different question, same exploration), the second call will be flagged as a repeat. The set should reset between user-message turns; only repeats *within a single tool-use loop iteration cluster* indicate runaway.

Concrete change: clear `seenCallSignatures` at the top of each outer iteration of the `while loopCount < maxLoops` loop, *or* scope it per-loop-iteration — not per-conversation.

Actually, looking more carefully: the set is in `run` which is per-user-message, so it does reset per user message. Good. The real bug is: within a single user-message loop, the agent might legitimately want to call `searchWardrobe(red)` first, then `searchWardrobe(red formal)` after seeing too many results — these have different signatures so they're fine. But it might also legitimately want to call `editOutfit(remove="sneakers")` twice on different outfits in the same turn. Today this is prevented. Consider keying signatures on `(name, input, target_outfit_id)` or whitelisting `editOutfit` from the repeat check.

### 2.4 Question card: "Other" with single-select is awkward
In `AgentQuestionCard`, when `multiSelect` is false and the user taps "Other", the card opens a TextField but offers no visible Submit button — the user has to know to press Return to send. A submit button (or a "Send" arrow inside the TextField) would be clearer. Also, `tapOther` clears `selectedOptions` even on multi-select toggle — review whether that's intended.

### 2.5 Streaming retry visibility
`setRetryStatus` shows "Retrying… (attempt 2/3)" in the bubble. Good. But the *reason* (overloaded vs network vs 429) is hidden. A subtitle with the cause would help users decide whether to wait or come back later. Also, the retry is only attempted on the *first* turn of a session before any text emits — if the API drops mid-stream on turn 5 of a tool chain, we surface "Something went wrong" with no retry. Consider:

- Add a manual "Retry" button on a failed assistant message bubble that re-runs the last loop iteration with the same history.
- Surface a one-line cause when overloaded so the user knows it's not their fault.

### 2.6 No user-visible cancel during streaming
`AgentViewModel.cancelCurrentTask` exists but isn't wired to UI. When the user changes their mind mid-stream they have no way to stop generation short of force-quitting. Add a "Stop" button that swaps in for the send button while `isSending` is true (familiar from ChatGPT).

### 2.7 The `pendingSeparatorMessageIDs` set has session-leak potential
It's cleared in `clearConversation` and removed on first delta after a tool use. But if a user message yields tool_use → no follow-up text → end_turn (rare but possible if the model finishes after a tool call without commenting), the pending separator never fires for that ID. Low impact but worth one defensive cleanup pass — clear the set in `finalizeStreamingMessage` too.

---

## 3. Tool Surface — New Capabilities

These are net-new tool ideas, ordered by how often they would actually be used.

### 3.1 `compareOutfits` tool
"How is my Casual Friday outfit different from my Saturday brunch one?" — today the agent has to call `searchOutfits` for both, then reason about the diff. A first-class `compareOutfits(outfit_ids: [String])` tool that returns a structured diff (overlapping items, distinct items, formality delta, color palette delta) would unblock natural questions about wardrobe structure.

### 3.2 `planOutfitsForWeek` tool
Given a list of days + occasions, return a rotation. Constraints: don't repeat anchor items consecutively, balance colors. This is fundamentally one batched `generateOutfit` call with cross-outfit deduplication. Great fit for Sunday-night planning, and a strong differentiator vs. a stylist app that only does one-at-a-time.

### 3.3 `findSimilarOutfit` tool
Anchored on a saved outfit: "give me three variations of this look — one dressier, one more casual, one for cooler weather". Generates variations by deltaing one axis at a time. Uses the existing relevance scorer with biased weights.

### 3.4 `tagOutfit` / `tagItems` tools
The agent can already create outfits. It can't currently apply or modify tags except as a side-effect of `generateOutfit`. A direct `tagOutfit(outfit_id, tags_to_add, tags_to_remove)` would close the loop on conversational tag management ("tag this as work, please") without a manual trip to `OutfitDetailView`.

### 3.5 `recordWornOutfit` tool
Tracks "what you wore today". This is a roadmap item (outfit calendar) but a thin version is one tool call away: an `Outfit.lastWornAt` field plus a `wear log`. Lets Athena answer "what do I usually wear on rainy Tuesdays" with real data instead of guesses.

### 3.6 `analyzeColorPalette` tool
Given the wardrobe, return the dominant palette and outliers. Powers questions like "do I lean cool or warm?", "what color do I have nothing of?". Half of this is already in `StyleSummary`, but exposing it as a tool the agent can call lets it reason about gaps in real time without a full style-analysis run.

### 3.7 Image input from the user
This is a bigger swing but the most user-facing of the new capabilities: let the user paste a photo into the chat ("style something like this") or anchor on an Instagram screenshot. Architecture: 
- New attachment path in `AgentView` input bar.
- Forward base64 image to Anthropic in the next user message (Claude vision is already used for scans).
- The agent reasons about the photo and calls `searchWardrobe` with an extracted description.

### 3.8 Voice input for chat
`Speech` framework + dictation button next to the send button. Especially valuable for "while getting dressed" usage where typing is friction. Reuse the existing Siri intent infrastructure thinking but in a chat context.

---

## 4. Tool Surface — Sharpening Existing Tools

### 4.1 `generateOutfit`: variation hint
After the first generation in a conversation, the prompt block "vary the occasion, color palette, or anchor item on subsequent calls" is in place but soft. A structured `variation_axis: "color" | "formality" | "anchor"` parameter would let the agent be explicit about what it's varying — leading to more obviously-different repeat suggestions.

### 4.2 `generateOutfit`: surface a "skipped duplicates" count
Today on `allSuggestionsDuplicate` we tell the user "no new combo available". The agent could be more useful by reporting *which* existing outfits the model proposed, and offering to generate a deliberate variation on one of them ("the closest existing pick is your Wednesday Office set — want me to riff on it?").

### 4.3 `editOutfit`: support reordering / rotating items
For users with multiple of the same category (3 jackets, 5 shirts) the most-asked edit is "swap the jacket". Today that's `remove_item_ids: [old_jacket]` + `add_item_ids: [new_jacket]`. A `swap_item` shortcut (`swap: [{from: id, to: id}]`) compresses this into one block with clearer semantics. Marginal but reduces tool call complexity.

### 4.4 `searchWardrobe`: synonym + color-family expansion
Currently `red` matches `red`, `red-toned` doesn't match `crimson` or `burgundy`. A small color-family table (`red ⊃ {crimson, burgundy, maroon, rust}`) would make the search dramatically more "stylist-feeling" without leaning on the model. Same for fabric: `wool ⊃ {tweed, flannel, cashmere}`.

### 4.5 `searchOutfits`: support negative tags
"What do I have that isn't formal?" — today there's no way to negate. Add `exclude_tags: [String]`. Tiny code change, high-utility query.

### 4.6 `askUserQuestion`: persist answer back to system prompt context
After the user picks an option, the answer goes to history as a user message ("In response to your question…"). Cleaner: also store the answer in a session-scoped "decided context" array surfaced in the fresh prompt as `THIS SESSION SO FAR: occasion=Smart Casual, vibe=relaxed`. This avoids the model needing to scan back through history to remember a decision made 4 turns ago. Tighter context, fewer mistakes.

### 4.7 `updateStyleInsight`: dedupe at input
`ObservationManager.recordObservation` has fuzzy matching (Jaccard > 0.4) to merge similar observations. Good. But the agent often re-records the same insight multiple turns in a row when the user repeats themselves. A short-circuit that returns "Insight already on record (last seen turn N)" instead of bumping the counter would prevent low-confidence observations from snowballing into high-confidence ones from noise.

---

## 5. UI / UX Polish

### 5.1 Outfit cards in chat: missing affordances
`AgentMessageBubble` outfit cards have Save / Update / Save-as-New buttons. A few useful additions:

- **Tap-to-expand reasoning.** The `outfit.reasoning` is computed and stored but never shown in chat. A collapsible "Why this works" disclosure would surface stylist intent and is the single best teaching moment in the app.
- **One-tap "Try a variation" button** that pipes "Generate another version of this outfit" into the input. Closes the loop on iteration without retyping.
- **Long-press copy** of the outfit description (text + items list) to share via Messages.

### 5.2 Wardrobe-item list in chat: pagination
The "Found N items" disclosure dumps all matches when expanded. For 50+ matches this is a long scroll. Cap visible at 12, with a "Show all" footer button.

### 5.3 Streaming indicator: more honest pacing
The phrase rotates every 2.5s but the actual work being done is often known (`toolStatus` is set). Today `toolStatus` overrides the rotating phrase — good. But when the model is between tool calls (waiting for first text token after a tool result), the indicator falls back to the rotating phrases. A specific "Stitching it together…" phrase for the post-tool-pre-text state would feel more truthful.

### 5.4 Athena name treatment
The system prompt says "introduce yourself as Athena" but the starter screen also says "Athena" prominently and the tab is titled "Athena". Athena introducing herself in the *first* assistant message of every conversation is a touch redundant after this. Consider: have the starter screen welcome message ("Hi, I'm Athena — your personal stylist…") render as a fake first assistant message, so the model doesn't have to repeat it. Also makes the chat feel pre-warmed.

### 5.5 New-chat affordance is hidden
The new-chat icon is `square.and.pencil` in the top-leading toolbar — discoverable but not obviously a "clear chat" button. Adding a label or a long-press tooltip ("New conversation") would help. Same icon as the iOS Mail compose button, which has the same problem there.

### 5.6 "Mode" toggle is hidden behind a chip
The Conversational vs Direct chip in the toolbar is small and easy to miss. Two ideas: 
- Add a one-line subtitle under "Athena" in the nav bar showing the active mode ("Athena · Chat" or "Athena · Direct").
- Surface mode in the starter screen so users get to choose before sending the first message.

### 5.7 Haptic feedback on key events
Saving an outfit, completing a question card, finalizing a generated outfit — all benefit from a light haptic (`UIImpactFeedbackGenerator`). Missing today.

### 5.8 Question card: keyboard handling for "Other"
When "Other" is selected and the TextField appears, the keyboard pushes the chat view but the card itself doesn't auto-scroll into view. Wrap in a `ScrollViewReader` and scroll-to on `isOtherSelected`.

### 5.9 Markdown rendering re-parses every render
`AgentMessageBubble.markdownText` calls `AttributedString(markdown:)` on every body recompute. For long bubbles streaming in, this is parsing the full text on every delta. Memoize per `message.id` + text length, or move parsing into `ChatMessage` (`var attributedText: AttributedString?` lazily computed).

### 5.10 Purchase suggestion cards: where to actually buy
The `PurchaseSuggestionDTO` describes what to buy in plain text. Adding a "Search on Google" / "Search on Nordstrom" button (URL-scheme to safari with the description as query) is one-line code and the most-asked-for follow-up.

### 5.11 Empty-state for failed generation
"Could not generate a valid outfit from the wardrobe" surfaces from the tool result back to the user as the agent's prose response. This often reads worse than it should ("Sorry, I couldn't make it work") with no actionable next step. Surface a one-tap "Show me what's missing" button that pipes into `suggestPurchases`.

---

## 6. Telemetry & Observability

### 6.1 The current telemetry is print-only
`AgentTelemetry` logs to console with `[AgentTelemetry]` prefix. Useful for local debugging but invisible in TestFlight. Once the Cloudflare Worker (v0.11b) is in place, the worker is the natural place to aggregate counts across users — the iOS side just needs to attach a small JSON header on each request:
```
X-Agent-Telemetry: {"unknown_alias":2,"fuzzy_fallback":0,"tool_calls":{"generateOutfit":1}}
```
Worker stores in Cloudflare Analytics or D1.

### 6.2 Missing counters
Worth adding:
- **Time-to-first-token** per turn (latency baseline).
- **Tool chain depth** distribution (how often does the loop run 3+, 5+ iterations?).
- **`allSuggestionsDuplicate` rate** — if it's high, that's a signal we need wardrobe-gap suggestions or a deliberate variation prompt.
- **Cancel rate** (user pressed Stop) — proxy for "the agent was going the wrong direction".

### 6.3 Surface telemetry to the user (developer setting)
Hidden under a Settings → Developer panel (gated by a flag), an "Athena diagnostics" view showing the last 20 tool calls and their durations would dramatically speed up bug triage. Already most of the data exists in `AgentTelemetry.snapshot()`.

---

## 7. Architecture & Code Hygiene

### 7.1 `AgentToolHost` exposes mutable dictionaries directly
`pendingOutfitItems`, `pendingOutfitTags`, `sourceOutfitIDForCopy`, `conversationGeneratedItemSets` are all `get set` on the protocol. The executor mutates them in-place from many sites. This works but defeats the "VM is sole observable" comment in the file. Consider tightening the surface to specific methods (`recordPendingOutfit(id, items, tags)`, `recordSourceMapping(copyID, sourceID)`) — easier to reason about, easier to add invariants, and keeps the executor honest.

### 7.2 `AgentToolExecutor.execute` returns a 4-tuple
`(String, [Outfit], [ClothingItem], String?)`. The conversation loop also has a `(String, [PurchaseSuggestionDTO])` for `suggestPurchases` and a `(String, [...], [...], ..., AgentQuestion?)` reassembly for `askUserQuestion`. Tuples this wide are easy to misread. Replace with a `ToolExecutionResult` struct shared between the two paths. Pure refactor, no behavior change.

### 7.3 `AgentConversationLoop.history` is `[[String: Any]]`
Untyped JSON is convenient for forwarding to Anthropic verbatim but makes compaction, repeat detection, and unit tests fragile. A typed `AnthropicMessage` enum (with `text`, `toolResultBlocks`, `assistantContent`) would make `compactHistoryIfNeeded` two lines instead of two nested loops. The serialization layer at the API boundary is the only place the dictionary form should appear.

### 7.4 The cached and fresh prompts have no test
`AgentPromptBuilder` is pure, ideal for snapshot tests. Today there are no tests in `AttirelyTests/` for the agent layer. A few snapshot tests on representative `AgentPromptContext` inputs would catch regressions when, say, someone tweaks the wardrobe block layout and breaks alias parsing on the model side.

### 7.5 `AgentService.toolDefinitions` lives in `AgentService.swift`
That file is otherwise tiny (just two API methods + the static array). Consider extracting `toolDefinitions` into `Services/AgentToolDefinitions.swift` or, better, generating it from the typed `*Input` structs in `AgentToolDTO.swift` so the JSON Schema stays in sync with Swift definitions automatically. Today they can drift silently.

### 7.6 Hard-coded `claude-sonnet-4-20250514`
Pull this into a single `AgentModelConfig` so model swaps and per-tool tier choices (see 1.1) are one-edit changes.

### 7.7 `effectiveMode` resolved on appear, not on profile change
`AgentView.onAppear` calls `viewModel.resolveEffectiveMode(from:)`. If the user changes their default mode in Settings while a chat is running in another tab, the next `sendUserMessage` will use the stale mode. Add `.onChange(of: activeProfile?.agentMode)` to re-resolve.

---

## 8. Things to Brainstorm (Bigger Bets)

These are not "do next sprint" items — they're directional ideas worth a half-hour of thinking.

### 8.1 Agent-as-journal: ambient learning across conversations
Today `behavioralNotes` accumulates. But there's no concept of "what did Athena and I talk about yesterday?" If conversations were persisted (§2.1) and the system prompt included a one-paragraph summary of the last 3 conversations, Athena would feel continuous in a way she doesn't today. The summary itself is one Haiku call after `clearConversation`.

### 8.2 Proactive nudges
The agent today is purely reactive. Two soft proactive moments are obviously valuable:
- **Morning nudge.** After granting the existing notification permission, push a "What are you wearing today?" notification at the user's preferred time. Tapping opens directly into a pre-filled chat with the day's weather.
- **New-item suggestion.** When the user adds a new item via Scan, queue a one-shot Athena message: "Nice, that camel coat opens up X new looks — want to see?"

### 8.3 Cross-outfit reasoning ("style audit")
A tool that runs over the entire saved-outfit collection and surfaces patterns: "you have 7 outfits anchored on the navy blazer and 0 on the green one — want to explore?". Half of this is Style Analysis, but presented as conversational findings rather than a static report card.

### 8.4 Structured outputs for outfit generation
Anthropic supports `tool_use` as the structured-output channel. Today `generateOutfit` returns DTOs parsed from text. Switching to a `respond_with_outfit` tool that the model is required to call when generating would cut a class of "the JSON isn't valid" errors and give Anthropic's caching a stable schema to lean on. Significant refactor; high quality bar.

### 8.5 Agent persistence across tabs
Today `AgentView` owns the `AgentViewModel`. Switching tabs (away and back) does not lose conversation state because SwiftUI keeps the view alive while the tab is in the bar — but a memory warning may. Promoting `AgentViewModel` to an app-level singleton (or at minimum a `@StateObject` in `AttirelyApp`) would make conversations survive memory pressure.

### 8.6 "Outfit critique" mode
Inverse of generation: "rate this outfit I'm wearing." User snaps a photo, agent analyzes via Claude vision, comments on fit/color/occasion-match. Pairs with §3.7 (image input). Big feature, but a clear differentiator vs. a static wardrobe app.

---

## 9. Things That Are Already Good — Don't Touch

For balance, the parts of the implementation that are sharp and shouldn't be re-litigated unless requirements change:

- **The two-prompt split (cached + fresh).** Right call architecturally. Just move more into the cached half (§1.2).
- **`OutfitMatcher` alias resolution.** The `4 ≤ len ≤ 8` hex prefix scheme is elegant — short enough for the model to remember, long enough to disambiguate at the wardrobe sizes Attirely targets. Don't over-engineer this.
- **`AgentConversationLoop` state machine.** The retry-while-no-text-emitted invariant is the right rule. The wrap-up turn after `maxLoops` is a clean safety net. The compaction window of "last 3 user turns kept verbatim" is a sensible default.
- **Parallel-safe tool partitioning.** The set `{searchWardrobe, searchOutfits, suggestPurchases}` is correct and the `withTaskGroup` reassembly is clean.
- **The single-shot askUserQuestion enforcement.** Having the second call rejected as a tool error is exactly the right error-channel choice — it teaches the model not to ask twice without polluting the user-facing UI.
- **`ChatMessage` as in-memory only.** Until persistence (§2.1) is needed, keeping this struct ephemeral is the right tradeoff.

---

## Suggested Sequencing

If everything above is on the table, a defensible 3-sprint shape:

**Sprint 1 (perf + correctness):** §1.1, §1.2, §1.3, §1.4, §2.2, §2.6, §4.5, §5.7, §5.9.

**Sprint 2 (UX polish + new tools):** §3.5 (recordWornOutfit), §4.1, §4.6, §5.1 (reasoning disclosure + try-a-variation), §5.10, §6.2.

**Sprint 3 (bigger swings):** §3.2 (planOutfitsForWeek), §3.7 (image input), §2.1 (persistence), §8.1 (cross-conversation memory).

Most items in §7 (architecture) can be folded into whichever sprint touches the relevant file — they don't need their own track.

---

## A Note on "no improvements needed"

The agent layer has been iterated on through six minor versions (v0.10.5 → v0.10.7) and has accumulated real care: alias addressing, parallel tools, history compaction, telemetry, a clean four-file split. None of the suggestions above represent bugs in the current implementation. They're paths forward, in a design that's already well past the "does this work?" question.

The single highest-ROI item, if only one thing got done, is **§1.2 — moving the wardrobe alias index into the cached system prompt**. It's a 20-line change with measurable impact on every multi-turn conversation in the app.
