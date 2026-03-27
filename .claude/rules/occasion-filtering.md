---
description: OccasionTier filtering system, progressive relaxation, wardrobe gap notes, style weight scaling
globs:
  - "Attirely/Helpers/OccasionFilter.swift"
  - "Attirely/ViewModels/OutfitViewModel.swift"
  - "Attirely/ViewModels/AgentViewModel.swift"
---

# Occasion-Based Filtering Rules

## OccasionTier Enum
- 10 tiers: Casual, Smart Casual, Business Casual, Business, Cocktail, Formal, Black Tie, White Tie, Gym/Athletic, Outdoor/Active
- 4 picker groups: Everyday, Work, Dress Code, Active (`OccasionTier.pickerGroups`)
- `OccasionTier(fromString:)` maps free-form strings (agent tool calls) via keyword matching

## Client-Side Filtering
- Hard-exclude by formality level + type keywords (substring match on `item.type`) + fabric
- Gym/Athletic uses **inverted logic**: items must match athletic keywords OR be casual Top/Bottom
- Small wardrobes (< 5 items) skip filtering entirely

## Progressive Relaxation
- If all items in a required category (Top, Bottom, Footwear) are filtered out, **all original items** for that category are restored
- This ensures the AI always has something to work with in critical categories

## Wardrobe Gap Notes
- `WardrobeGap` struct: category, description, investment suggestion
- Generated when progressive relaxation triggers; context-aware by category × occasion (e.g., Footwear for Black Tie → "patent leather oxfords")
- Client-side gaps merged with AI-returned `wardrobe_gaps` via `OccasionFilter.mergeGaps()`
- Persisted on `Outfit.wardrobeGaps: String?` (JSON-encoded `[String]`), decoded via `wardrobeGapsDecoded`
- Displayed in OutfitDetailView (warning card) and AgentMessageBubble (inline lightbulb notes)

## AI Prompt Enhancement
- `OccasionFilterContext` carries tier, style weight, gaps, relaxed categories to `AnthropicService.generateOutfits`
- **Style weight scaling**: HIGH (casual) → MEDIUM (business) → LOW (formal/activity) — controls style profile influence
- **Priority hierarchy**: casual prioritizes aesthetics; formal prioritizes dress code compliance
- Dress code instructions injected per tier (e.g., Black Tie strict rules, Gym function-first)
