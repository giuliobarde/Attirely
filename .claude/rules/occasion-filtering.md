---
description: OccasionTier filtering system, FilteringMode gradient, formality floor, relevance scoring, wardrobe gap notes
globs:
  - "Attirely/Helpers/OccasionFilter.swift"
  - "Attirely/Helpers/RelevanceScorer.swift"
  - "Attirely/Helpers/ObservationManager.swift"
  - "Attirely/ViewModels/OutfitViewModel.swift"
  - "Attirely/ViewModels/AgentViewModel.swift"
---

# Occasion-Based Filtering & Relevance Scoring Rules

## OccasionTier Enum
- 10 tiers: Casual, Smart Casual, Business Casual, Business, Cocktail, Formal, Black Tie, White Tie, Gym/Athletic, Outdoor/Active
- 4 picker groups: Everyday, Work, Dress Code, Active (`OccasionTier.pickerGroups`)
- `OccasionTier(fromString:)` maps free-form strings (agent tool calls) via keyword matching

## Tier-Based Filtering Gradient (FilteringMode)
- **`.none`** (Casual, Smart Casual): no type/formality/fabric exclusions — only formality floor enforced. AI + style profile handle item selection
- **`.light`** (Business Casual, Business, Outdoor/Active): exclude only egregiously wrong items (flip flops, crocs, gym shorts, sports bras, running shoes, tank tops) + formality floor
- **`.moderate`** (Cocktail, Formal): exclude clearly casual items (sneakers, sweatpants, joggers, hoodies, crop tops, gym/athletic) + Denim/Fleece fabrics + formality floor
- **`.strict`** (Black Tie, White Tie): full hard-exclude filtering (formality + type keywords + fabric) + formality floor — dress codes are codified
- **`.inverted`** (Gym/Athletic): items must match athletic keywords OR be casual Top/Bottom + formality floor

## Item Formality Floor
- Optional `formalityFloor: String?` on `ClothingItem` — AI-detected on scan, user-editable in ItemDetailView
- When set, the item only appears in outfits at or above that tier (e.g., tuxedo `formalityFloor: "Black Tie"`)
- `OccasionFilter.passesFormalityFloor()` enforced in ALL filtering modes including `.none`
- Most items have nil floor (wearable anywhere); only truly occasion-locked items get a floor

## Relevance-Based Pre-Selection (RelevanceScorer)
- After OccasionFilter runs, `RelevanceScorer.selectCandidates()` scores and selects ~35 items for token efficiency
- **Scoring weights**: outfit frequency (0.25), favorite bonus (0.20), formality alignment (0.20), agent observations (0.15), seasonal match (0.10), usage score (0.10)
- **Category-balanced selection**: min 4 items per required category (Top, Bottom, Footwear), remaining slots filled by top-scored items across all categories
- Items scoring > 0.7 are annotated as `[STRONG MATCH]` in the prompt — soft hints, not constraints
- Pools <= 35 items skip selection (all items scored and returned)

## Agent Behavioral Observations
- `AgentObservation` structs stored as JSON on `StyleSummary.behavioralNotes`
- 9 categories: formalityPreference, colorAversion/Preference, fabricAversion/Preference, occasionBehavior, itemAversion/Preference, generalStyle
- **Threshold variance**: explicit statements (high confidence) → threshold 1; behavioral patterns → threshold 2-3; inferred patterns → threshold 3-5
- Active observations injected into agent system prompt (cap 15) and outfit generation prompt
- Negative signals captured from: explicit dislikes, editOutfit item removals (with occasion context)
- `ObservationManager` handles recording, fuzzy matching (Jaccard similarity > 0.4), classification, pruning (90-day stale, 30 max)
- `StyleViewModel.graduateObservations()` auto-resolves well-reinforced low-impact observations after style analysis

## Progressive Relaxation
- If all items in a required category (Top, Bottom, Footwear) are filtered out, **all original items** for that category are restored
- Applies to `.light`, `.moderate`, `.strict`, `.inverted` modes (not `.none` since nothing is filtered)

## Wardrobe Gap Notes
- `WardrobeGap` struct: category, description, investment suggestion
- Generated when progressive relaxation triggers; context-aware by category × occasion
- Client-side gaps merged with AI-returned `wardrobe_gaps` via `OccasionFilter.mergeGaps()`
- Persisted on `Outfit.wardrobeGaps: String?` (JSON-encoded `[String]`)

## AI Prompt Enhancement
- `OccasionFilterContext` carries tier, style weight, gaps, relaxed categories to `AnthropicService.generateOutfits`
- `observationContext: String?` — behavioral notes injected as USER BEHAVIORAL PATTERNS
- `itemRelevanceHints: [UUID: Double]?` — annotates high-scoring items in the item list
- **Style weight scaling**: HIGH (casual) → MEDIUM (business) → LOW (formal/activity)
- **Priority hierarchy**: casual prioritizes aesthetics; formal prioritizes dress code compliance
