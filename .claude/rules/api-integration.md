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
- **5 tools**: `generateOutfit(occasion?, constraints?)`, `searchOutfits(query?, tags?)`, `searchWardrobe(query)`, `updateStyleInsight(insight, confidence, category?, signal?)`, `editOutfit(outfit_name, remove_items?, add_items?, new_name?, new_occasion?)`
- **Intent detection**: "new/different/surprise" → `generateOutfit`, "familiar/go-to/worn before" → `searchOutfits`, "specific items" → `searchWardrobe`, "modify/swap/add/remove" → `editOutfit`, ambiguous → `generateOutfit`
- `editOutfit`: fuzzy item matching via word overlap scoring on type/color/category/fabric. In-place `Outfit` mutation (reference type), composition validation via `OutfitLayerOrder.warnings()`
- `searchOutfits`: filters by tag names and/or query text, favorites first, returns top 5 as inline cards
- Streaming loop: max 5 iterations with `Task` cancellation support (`currentTask` property)
- Full wardrobe loaded on-demand via tool execution, not in system prompt (token budget)
- Outfits in chat are ephemeral until user taps "Save Outfit" → SwiftData insert + weather snapshot

## Weather API
- **Primary**: Apple WeatherKit (requires entitlement)
- **Fallback**: Open-Meteo (`GET https://api.open-meteo.com/v1/forecast`), no API key needed
- Returns `WeatherSnapshot` (ephemeral) with current conditions + 12-hour forecast
- Location via CoreLocation with "when in use" permission
