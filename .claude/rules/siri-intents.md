---
description: App Intents for Siri/HomePod, outfit selection algorithm, spoken summaries
globs:
  - "Attirely/Intents/**"
---

# Siri & App Intents Rules

## Architecture
- **In-app App Intents** — runs in main app process (system launches app in background), no extension target
- `ModelContainer` explicitly created in `AttirelyApp.init()` and registered via `AppDependencyManager.shared.add(dependency:)` for intent dependency injection
- Single-turn only — no back-and-forth dialog flows
- HomePod triggers via Siri intent forwarding to iPhone

## Intents
- `WhatToWearTodayIntent` — "What should I wear today?" with weather + preferences context
- `WhatToWearToIntent` — "What should I wear to [occasion]?" with `OutfitOccasion` AppEnum
- `OutfitOccasion` cases: casual, date night, work, formal, cocktail, black tie, gym, travel, outdoor
- `AttirelyShortcuts` — `AppShortcutsProvider` with natural Siri phrases for both intents

## Siri Outfit Selection (`SiriOutfitService`)
- Queries outfits tagged `"siri"` → filters by season/weather/occasion → **random selection** from pool
- Season: checks `seasonAtCreation` and seasonal tags against current weather-adapted season
- Weather: outfits within ±10°C pass; outfits without weather data always pass
- Occasion: fuzzy match on `occasion` field and tags; relaxes if filter eliminates all
- `lastSuggestedBySiriAt: Date?` tracked for analytics (does not influence selection)

## Spoken Summaries
- **Tagged outfits**: template-based — "How about [name]? It's your [color] [type], [color] [type]..." — instant, no API call
- **AI-generated outfits**: use `spokenSummary` from `OutfitSuggestionDTO`

## AI Generation Fallback
- `isSiriAIGenerationEnabled` on `UserProfile` (default false)
- When enabled + no siri-tagged match: generates via `AnthropicService.generateOutfits()`, auto-saves with "siri" tag
- Non-streaming agent path (`AgentService.sendMessage()`) preserved specifically for Siri
- Weather: uses profile location override if set, else `LocationService`, falls back to `SeasonHelper.currentSeason()`
