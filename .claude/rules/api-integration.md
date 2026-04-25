---
description: Anthropic API, agent tools, SSE streaming, outfit generation pipeline, weather API conventions
globs:
  - "Attirely/Services/**"
  - "Attirely/Models/*DTO*"
  - "Attirely/Models/SSETypes.swift"
---

# API Integration Rules

## Anthropic API
- Endpoint: `POST https://api.anthropic.com/v1/messages`
- Auth: `x-api-key` from `Config.plist` via `ConfigManager`
- Model: `claude-sonnet-4-20250514`, version header: `anthropic-version: 2023-06-01`
- Images: base64-encoded JPEG at 0.6 compression quality
- Single-image scan: `analyzeClothingWithOutfitDetection()` returns `ScanResponseDTO` (wrapper with `items` + optional `outfit` suggestion). Fallback: if wrapper decode fails, falls back to `[ClothingItemDTO]` with `outfit: nil`
- Multi-image scan: `analyzeClothingMultiImage()` returns flat `[ClothingItemDTO]` (no outfit detection)
- All AI requests use 2048 max tokens (scan uses 4096)

## Outfit Generation Pipeline
- Text-only request — sends **scored candidate** wardrobe item attributes with UUIDs (no images)
- Returns `OutfitSuggestionDTO` with `name`, `occasion`, `item_ids`, `reasoning`, `spoken_summary`, `tags`, `wardrobe_gaps`
- Flow: `OccasionFilter` tier-based filtering → `RelevanceScorer` scores + selects ~35 candidates → candidates + `OccasionFilterContext` + `observationContext` + `itemRelevanceHints` sent to AI → response validated
- Client-side validation: minimum 3 matched item IDs; skip outfits with hallucinated IDs
- Deduplication: `existingOutfitItemSets` (sorted item-ID arrays for up to 20 existing outfits)
- AI auto-tagging: available tag names injected into prompt; Claude returns 1-3 tags; resolved via `TagManager.resolveTags`, unrecognized names silently dropped
- Weather-adaptive: temperature-based layering/fabric, precipitation awareness
- Comfort preferences injected as hard constraints; style summary included when available
- Behavioral observations injected as `USER BEHAVIORAL PATTERNS` block; items scoring > 0.7 annotated with `[STRONG MATCH]`

## Style Analysis
- Sends wardrobe items + outfit compositions (tiered: favorited > manual > AI-generated) + previous style summary
- Returns `StyleAnalysisDTO`: overall identity, style modes, temporal notes, gap observations, weather behavior
- Initial: full wardrobe (capped 60 items). Incremental: three-tier (favorites full, new full, existing compact)

## Style Agent (Chat)
- **SSE streaming**: `AgentService.streamMessage()` → `SSEStreamParser` → `ContentBlockAccumulator` → text deltas update UI immediately; tool_use blocks accumulate silently
- Non-streaming path (`AgentService.sendMessage()`) preserved for Siri intents
- System prompt injects: weather, comfort preferences, style summary, wardrobe category counts
- **7 tools**: `generateOutfit(occasion?, constraints?, must_include_item_ids?, must_include_items?)`, `searchOutfits(query?, tags?)`, `searchWardrobe(query)`, `updateStyleInsight(insight, confidence, category?, signal?)`, `editOutfit(outfit_id?, outfit_name?, remove_item_ids?, add_item_ids?, remove_items?, add_items?, new_name?, new_occasion?)`, `suggestPurchases(category?)`, `askUserQuestion(question, options, allow_other?, multi_select?)`
- **Intent detection**: "new/different/surprise" → `generateOutfit`, "familiar/go-to/worn before" → `searchOutfits`, "specific items" → `searchWardrobe`, "modify/swap/add/remove" → `editOutfit`, "what to buy" → `suggestPurchases`, choices/preferences → `askUserQuestion`, otherwise ambiguous → `generateOutfit`
- **ID addressing** (`OutfitMatcher`): 6-hex UUID prefix aliases (e.g. `a3f91c`) are the preferred channel. Tool result formatters prefix wardrobe/outfit rows with the alias; the system prompt inlines a wardrobe alias index when wardrobe ≤ 40 items. `*_item_ids` and `outfit_id` resolve via `OutfitMatcher.resolveAlias` (deterministic, unique-prefix). Free-form `*_items` / `outfit_name` retained as fallback — resolved via fuzzy word-overlap on type/color/category/fabric/pattern when no ID was cited. Aliases are plumbing only: the cached system prompt instructs the agent never to leak them to the user.
- `editOutfit`: for conversation outfits mutates in place; for saved outfits produces an ephemeral variant (`sourceOutfitIDForCopy`) so the user picks Update Original vs. Save as New via buttons. Composition validation via `OutfitLayerOrder.warnings()`.
- `searchOutfits`: filters by tag names and/or query text, favorites first, returns top 5 as inline cards
- **Architecture** (v0.10.5): agent plumbing split into four files — `AgentConversationLoop` (SSE loop, tool-use state machine, retry/wrap-up, history compaction), `AgentToolExecutor` (7 tool implementations, ID-addressed resolution), `AgentPromptBuilder` (cached + fresh system prompt, wardrobe alias index), `OutfitMatcher` (alias + fuzzy resolution). `AgentViewModel` is the observable facade that conforms to `AgentToolHost` + `AgentLoopHost`.
- **Parallel tool execution** (v0.10.6): per tool-use iteration, read-only tools (`searchWardrobe`, `searchOutfits`, `suggestPurchases`) dispatch through `withTaskGroup`; mutating tools (`generateOutfit`, `editOutfit`, `updateStyleInsight`, `askUserQuestion`) run sequentially. Outcomes are aggregated keyed by `tool_use_id` and reassembled in the model's original call order so the UI and tool_result sequence stay stable.
- **History compaction** (v0.10.6): `tool_result.content` in turns older than the last 3 user messages is replaced with `"[tool result elided to save tokens]"`. User text, assistant text, and `tool_use` blocks are kept verbatim. `tool_use_id` pairing is preserved (required by the Anthropic API). Runs after every tool-result append in `AgentConversationLoop.run`; idempotent.
- **Polish pass** (v0.10.7): `askUserQuestion` is single-shot per turn — duplicate calls in the same turn get an error `tool_result` and the second `AgentQuestion` is dropped. Tool results are factual (rendering directives moved into a TOOL RESULT RENDERING block in the cached system prompt). `AgentTelemetry` (Helpers/) tracks tool-call distribution, unknown-alias rate, fuzzy-fallback rate, duplicate questions, malformed JSON, and pruned pending outfits — printed as `[AgentTelemetry]` console logs. `AgentViewModel.pruneOrphanedPendingOutfits()` runs after each turn so abandoned outfits don't accumulate in pending dictionaries. `SSETypes.parseToolInputJSON` logs malformed tool-use JSON instead of silently returning `{}`. Tool descriptions in `AgentService.toolDefinitions` consolidated — routing rules live only in the cached system prompt's INTENT DETECTION section.
- Streaming loop: max 10 tool-use iterations + runaway detector (repeat `(tool, input)` signature triggers wrap-up turn with `tools: []`). Full `Task` cancellation support via `currentTask`.
- Full wardrobe loaded on-demand via tool execution, not in system prompt (token budget)
- Outfits in chat are ephemeral until user taps "Save Outfit" → SwiftData insert + weather snapshot

## Weather API
- **Primary**: Apple WeatherKit (requires entitlement)
- **Fallback**: Open-Meteo (`GET https://api.open-meteo.com/v1/forecast`), no API key needed
- Returns `WeatherSnapshot` (ephemeral) with current conditions + 12-hour forecast
- Location via CoreLocation with "when in use" permission
