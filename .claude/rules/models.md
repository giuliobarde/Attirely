---
description: SwiftData model gotchas, DTO conventions, Tag scope mechanics, relationship patterns
globs:
  - "Attirely/Models/**"
---

# Model Layer Rules

## Gotchas
- `ClothingItem` uses `itemDescription` (not `description`) to avoid NSObject conflict
- `Outfit.displayName` computed property falls back: `name` → `occasion` → formatted date
- `Tag.scopeRaw` stores `TagScope` enum (.outfit, .item) as String; uniqueness by name+scope enforced in code via `TagManager`, not a DB constraint
- `Outfit.wardrobeGaps: String?` is JSON-encoded `[String]`; use `wardrobeGapsDecoded` computed property

## DTO Conventions
- DTOs own their `CodingKeys` for snake_case API ↔ camelCase Swift mapping
- `ClothingItemDTO.tags: [String]` and `OutfitSuggestionDTO.tags: [String]` use resilient decoders (default to empty array on failure)
- `OutfitSuggestionDTO.wardrobeGaps: [String]` — resilient decoder
- `StyleAnalysisDTO.styleModes` defaults to empty array if null
- `OutfitSuggestionDTO.spokenSummary: String?` — conversational voice description for Siri

## Structural Rules
- No business logic, no API calls, no UI code in model files
- `ChatMessage` is ephemeral in-memory struct (no SwiftData) for agent conversation
- `AgentToolDTO.swift` contains `ToolUseBlock`, `AgentTurn`, and typed tool input structs (5 tools)
- `SSETypes.swift` contains `SSEEvent` enum + `ContentBlockAccumulator` for streaming
