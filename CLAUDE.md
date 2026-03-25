# Attirely — Project Guide

## What is Attirely?
A wardrobe management iOS app. Users scan clothing via camera/photo library, the app identifies items using Claude's vision API, and builds a persistent digital wardrobe. Users can generate outfits manually or with AI assistance.

## IMPORTANT — Maintenance Rule
After implementing a version milestone, update this `CLAUDE.md` (current state, project structure, roadmap) to reflect the changes. This includes new files, updated descriptions, and roadmap progress. Do NOT skip this step.

## Tech Stack
- **Language:** Swift (strict concurrency enabled)
- **UI:** SwiftUI
- **Min Target:** iOS 26.2
- **Storage:** SwiftData
- **AI:** Anthropic Claude API (vision + outfit generation + conversational style agent)
- **Architecture:** MVVM
- **Dependencies:** None. Apple frameworks + URLSession only. Do NOT add SPM packages, CocoaPods, or any third-party dependencies without explicit approval.

## Build & Run
1. Copy `Attirely/Resources/Config.plist.example` → `Config.plist`, add Anthropic API key
2. Open in Xcode 26+, build and run (Cmd+R)
3. Camera requires physical device; simulator supports photo library only

## Project Structure
```
Attirely/
├── App/AttirelyApp.swift
├── Models/
│   ├── ClothingItem.swift          # SwiftData @Model (persistent)
│   ├── ClothingItemDTO.swift       # Codable struct (API parsing, includes tags field)
│   ├── ScanSession.swift           # SwiftData @Model
│   ├── Outfit.swift                # SwiftData @Model (outfit collection + weather snapshot + wardrobe gaps)
│   ├── OutfitSuggestionDTO.swift   # Codable struct (AI outfit parsing, + spokenSummary, wardrobeGaps)
│   ├── StyleAnalysisDTO.swift      # Codable structs (AI style analysis parsing)
│   ├── ChatMessage.swift           # Ephemeral struct (agent chat messages, no persistence)
│   ├── AgentToolDTO.swift          # Tool call/result types for agent tool_use (5 tools: generateOutfit, searchOutfits, searchWardrobe, updateStyleInsight, editOutfit)
│   ├── SSETypes.swift              # SSEEvent enum + ContentBlockAccumulator for streaming response parsing
│   ├── WeatherData.swift           # Ephemeral structs (current + hourly weather)
│   ├── UserProfile.swift           # SwiftData @Model (user prefs, profile, style questionnaire)
│   ├── StyleSummary.swift          # SwiftData @Model (template/AI style summary)
│   └── Tag.swift                   # SwiftData @Model (scoped tagging: separate outfit + item pools via TagScope)
├── Services/
│   ├── AnthropicService.swift      # Claude API calls (scan, duplicates, outfits, style analysis, agent + SSE streaming)
│   ├── AgentService.swift          # Stateless agent conversation service (tool_use, multi-turn, streaming)
│   ├── SSEStreamParser.swift       # SSE byte stream parser (URLSession.AsyncBytes → AsyncThrowingStream<SSEEvent>)
│   ├── ConfigManager.swift         # Reads API key from Config.plist
│   ├── ImageStorageService.swift   # Save/load images on disk
│   ├── LocationService.swift       # CoreLocation wrapper for user location
│   └── WeatherService.swift        # WeatherKit + Open-Meteo fallback
├── ViewModels/
│   ├── ScanViewModel.swift
│   ├── WardrobeViewModel.swift
│   ├── OutfitViewModel.swift       # Outfit creation, generation, favorites
│   ├── AgentViewModel.swift        # Chat agent conversation state, SSE streaming loop, tool-use, outfit editing, context building
│   ├── WeatherViewModel.swift      # Weather state, location, fetch coordination
│   ├── ProfileViewModel.swift      # Profile state, analytics, geocoding
│   └── StyleViewModel.swift        # AI style analysis state, debounce, merge, agent insights
├── Views/
│   ├── MainTabView.swift           # TabView (Agent + Wardrobe + Outfits + Profile)
│   ├── ResultsView.swift
│   ├── ClothingItemCard.swift
│   ├── ImagePicker.swift           # UIImagePickerController wrapper
│   ├── WardrobeView.swift          # Browsable wardrobe (grid/list) + scan + tag filter bar + bulk selection
│   ├── ItemDetailView.swift        # View/edit item details + tag editing
│   ├── DuplicateWarningBanner.swift
│   ├── DuplicateReviewSheet.swift
│   ├── OutfitsView.swift           # Outfit list with favorites filter
│   ├── OutfitDetailView.swift      # Layer-ordered card stack view with inline edit mode
│   ├── OutfitRowCard.swift         # Compact outfit card for list
│   ├── OutfitGenerationContextSheet.swift  # AI generation context picker (grouped OccasionTier picker)
│   ├── ItemPickerSheet.swift       # Manual outfit item selection
│   ├── AddItemView.swift           # Manual wardrobe item entry form + tag selection
│   ├── WeatherWidgetView.swift     # Compact toolbar weather indicator
│   ├── WeatherDetailSheet.swift    # Full weather modal with hourly forecast
│   ├── AgentView.swift             # Chat agent tab (starter screen + fullScreenCover chat, unsaved outfit warning)
│   ├── AgentMessageBubble.swift    # Agent message rendering (text, outfit cards, item refs, insights)
│   ├── ProfileView.swift           # Profile tab (details, prefs, analytics)
│   ├── WardrobeAnalyticsView.swift # Swift Charts wardrobe analytics
│   ├── TagChipView.swift           # Reusable tag chip component (selected/default states, custom colors)
│   ├── TagFilterBar.swift          # Scope-aware horizontal scrolling tag filter (Outfits + Wardrobe tabs)
│   ├── TagPickerSheet.swift        # Scope-aware tag toggle/create via Binding (outfits + items)
│   ├── TagManagementView.swift     # Full tag CRUD screen by scope (Profile → Manage Tags)
│   ├── BulkTagEditSheet.swift      # Scope-aware bulk tag editor (outfits + items)
│   └── OutfitEditItemPicker.swift  # Item picker for outfit editing (add items to existing outfit)
├── Intents/
│   ├── SiriOutfitService.swift     # Siri outfit selection algorithm (tagged pool → AI fallback)
│   ├── WhatToWearTodayIntent.swift # "What should I wear today?" App Intent
│   ├── WhatToWearToIntent.swift    # "What should I wear to [occasion]?" App Intent + OutfitOccasion AppEnum (incl. cocktail, black tie)
│   └── AttirelyShortcuts.swift     # AppShortcutsProvider with Siri phrases
├── Helpers/
│   ├── Theme.swift                 # Brand design system: color tokens, ViewModifiers, ButtonStyles
│   ├── ColorMapping.swift          # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   ├── OutfitLayerOrder.swift      # Category → layer sort order + composition warnings
│   ├── SeasonHelper.swift          # Season detection from date/weather
│   ├── TemperatureFormatter.swift  # °C/°F formatting helper
│   ├── StyleSummaryTemplate.swift  # Deterministic style summary from questionnaire
│   ├── StyleContextHelper.swift    # Shared comfort/style/weather context builders (DRY helper)
│   ├── TagSeeder.swift             # Idempotent predefined tag seeding (outfit + item scopes)
│   ├── TagManager.swift            # Shared tag CRUD helper (create, rename, delete, resolve)
│   └── OccasionFilter.swift        # OccasionTier enum, hybrid client-side item filtering, wardrobe gap generation
└── Resources/
    ├── Config.plist.example
    └── Assets.xcassets
```

## Xcode Project Conventions
- `PBXFileSystemSynchronizedRootGroup` is enabled — new source files added to `Attirely/` are auto-detected. Do NOT manually edit `.pbxproj` to add source files.
- `GENERATE_INFOPLIST_FILE = YES` — add Info.plist keys via `INFOPLIST_KEY_*` build settings, not a standalone Info.plist file.
- `Config.plist` is git-ignored (contains API key). Never commit it.

## Architecture Rules (MVVM)

### Models (`Models/`)
- `ClothingItem` is a SwiftData `@Model` class for persistence with `tags: [Tag]` relationship. `ClothingItemDTO` is a `Codable` struct for API parsing (includes `tags: [String]` with resilient decoder). `ScanSession`, `Outfit`, `UserProfile`, `StyleSummary`, and `Tag` are SwiftData `@Model`s. `Tag` uses `TagScope` (.outfit, .item) for separate pools with `scopeRaw` stored property. `OutfitSuggestionDTO` (includes `tags: [String]` with resilient decoder) and `StyleAnalysisDTO` are `Codable` structs for AI response parsing.
- `ChatMessage` is an ephemeral in-memory struct (no SwiftData) for agent conversation messages. `AgentToolDTO.swift` contains `ToolUseBlock`, `AgentTurn`, and typed tool input structs for Claude tool_use parsing (4 tools: generateOutfit, searchOutfits, searchWardrobe, updateStyleInsight).
- No business logic, no API calls, no UI code.
- DTOs own their `CodingKeys` for JSON mapping (snake_case API ↔ camelCase Swift).
- `ClothingItem` uses `itemDescription` (not `description`) to avoid NSObject conflict.
- `Outfit` has a `displayName` computed property that falls back from `name` → `occasion` → formatted date.

### Services (`Services/`)
- Handle all external I/O: API calls, file system, config reading.
- Return Swift types, not raw JSON. Throw typed errors, not generic ones.
- Services should be stateless where possible. The view model owns state.

### ViewModels (`ViewModels/`)
- Owns the mutable state that views observe (`@Observable`).
- Calls into services, maps results to view-ready state.
- Contains presentation logic (e.g., "should the retry button be visible?") but NOT layout/styling.
- One view model can serve multiple related views (e.g., `ScanViewModel` serves both `HomeView` and `ResultsView`).

### Views (`Views/`)
- Purely declarative SwiftUI. No `URLSession`, no file I/O, no business logic.
- Read state from view models. Trigger actions by calling view model methods.
- Extract reusable components into their own files (e.g., `ClothingItemCard`).

### Helpers (`Helpers/`)
- Pure utility functions with no side effects. No state, no I/O.
- `Theme.swift` — adaptive light/dark mode design system using `Color(UIColor { traitCollection in ... })`. Champagne accent is fixed across modes. Provides color tokens, semantic aliases, ViewModifiers (`.themeCard()`, `.themePill()`, `.themeTag()`), and ButtonStyles (`.themePrimary`, `.themeSecondary`). All views use theme tokens — never hardcode colors.
- `ColorMapping` translates color name strings to SwiftUI `Color` values (for clothing item display, not UI theme).

## Swift & Concurrency Conventions

### Actor Isolation
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide. All types default to `@MainActor`.
- For types that must run off the main actor, explicitly annotate with `nonisolated` or a custom actor.
- Service methods performing network I/O should be `async` and are fine on `@MainActor` since URLSession.data is already non-blocking.

### Async/Await
- Use structured concurrency (`async/await`) everywhere. No completion handlers, no Combine publishers for new code.
- Call async service methods from view models inside `Task { }` blocks.
- Always handle `Task` cancellation gracefully — check `Task.isCancelled` in long operations.

### Error Handling
- Define domain-specific error enums (e.g., `AnthropicError`, `ConfigError`), not raw strings.
- Services throw errors. ViewModels catch them and map to user-facing state (error message strings, retry flags).
- Views never see raw errors — they see view model properties like `errorMessage: String?` and `canRetry: Bool`.
- Never force-unwrap (`!`) network responses or JSON parsing results. Always use `guard let` / `if let` or `try/catch`.

## API Integration Details

### Anthropic API
- Endpoint: `POST https://api.anthropic.com/v1/messages`
- Auth header: `x-api-key` read from `Config.plist` via `ConfigManager`
- Model: `claude-sonnet-4-20250514`
- API version header: `anthropic-version: 2023-06-01`
- Images sent as base64-encoded JPEG at 0.6 compression quality
- Response parsing: extract `content[0].text`, decode as JSON array of `ClothingItemDTO`

### Outfit Generation
- Text-only request — sends **filtered** wardrobe item attributes with UUIDs (occasion-based pre-filtering via `OccasionFilter`)
- Generates exactly 1 outfit per request; returns `OutfitSuggestionDTO` with `name`, `occasion`, `item_ids`, `reasoning`, `spoken_summary`, `tags`, `wardrobe_gaps`
- **Occasion-based hybrid filtering** (`OccasionFilter.swift`):
  - `OccasionTier` enum: Casual, Smart Casual, Business Casual, Business, Cocktail, Formal, Black Tie, White Tie, Gym/Athletic, Outdoor/Active
  - Client-side hard-exclude by formality level + type keywords + fabric (e.g., sneakers excluded for Formal, denim excluded for Black Tie)
  - **Progressive relaxation**: if filtering empties a required category (Top/Bottom/Footwear), all original items in that category are restored
  - **Wardrobe gap notes**: when filters relax, generates context-aware investment suggestions (e.g., "No black-tie footwear found. Consider investing in patent leather oxfords.")
  - Gap notes merged from client-side filter + AI response, persisted on `Outfit.wardrobeGaps`, displayed in OutfitDetailView and AgentMessageBubble
  - Small wardrobes (< 5 items) skip filtering entirely
- **Style weight scaling**: style profile relevance varies by occasion — HIGH for casual, MEDIUM for business, LOW for formal/activity (dress code compliance first)
- **Dress code instructions**: occasion-specific rules injected into prompt (e.g., Black Tie strict dress code, Gym function-first)
- **Priority hierarchy**: shifts by occasion — casual prioritizes aesthetics, formal prioritizes dress code compliance
- **AI auto-tagging**: available tag names injected into prompt; Claude returns 1-3 tag names per outfit; client-side resolution via normalized name lookup, unrecognized names silently dropped
- Deduplication via `existingOutfitItemSets` (sorted item-ID arrays for up to 20 existing outfits)
- Client-side validation: minimum 3 matched items before saving; degraded outfits with hallucinated IDs are skipped
- Weather-adaptive: temperature-based layering/fabric rules, precipitation awareness
- Comfort preferences injected as hard constraints; style summary included when available
- Uses 2048 max tokens

### Style Analysis
- Text-only request — sends wardrobe items + outfit compositions (tiered: favorited > manual > AI-generated) + previous style summary
- Returns `StyleAnalysisDTO`: overall identity, style modes, temporal notes, gap observations, weather behavior
- Initial analysis: full wardrobe (capped at 60 items). Incremental: three-tier item data (favorites full detail, new items full detail, existing items compact summary)
- `StyleAnalysisDTO.styleModes` defaults to empty array if null (resilient decoder)
- Uses 2048 max tokens

### Style Agent
- **SSE Streaming**: agent responses stream token-by-token via `AgentService.streamMessage()` → `SSEStreamParser` → `ContentBlockAccumulator`. Text deltas update UI immediately; tool_use blocks accumulate silently until complete. Each tool-use loop iteration is a separate streaming request
- Non-streaming path (`AgentService.sendMessage()` / `AnthropicService.sendAgentRequest`) preserved for Siri intents
- Uses `system` top-level key for persistent context injection (weather, comfort preferences, style summary, wardrobe category counts)
- Claude `tool_use` with five tools: `generateOutfit(occasion?, constraints?)`, `searchOutfits(query?, tags?)`, `searchWardrobe(query)`, `updateStyleInsight(insight, confidence)`, `editOutfit(outfit_name, remove_items?, add_items?, new_name?, new_occasion?)`
- **Intent detection**: system prompt classifies user intent — "new/different/surprise" → `generateOutfit`, "familiar/go-to/worn before" → `searchOutfits`, "specific items" → `searchWardrobe`, "modify/swap/add/remove" → `editOutfit`, ambiguous → `generateOutfit`
- **Conversational outfit editing** via `editOutfit` tool: fuzzy item matching by type/color description, in-place mutation of ephemeral Outfit objects, composition validation via `OutfitLayerOrder.warnings()`. Edited outfits remain unsaved until user taps "Save Outfit"
- `searchOutfits` filters saved outfits by tag names and/or query text, sorts favorites first, returns top 5 as inline outfit cards
- **Streaming loop** in `AgentViewModel` (max 5 iterations) with `Task` cancellation support. `currentTask` property enables mid-stream cancellation on chat dismiss
- Full wardrobe items loaded on-demand via tool execution, not in system prompt (token budget). Outfit overview (count + favorites) in system prompt
- **Chat as fullScreenCover**: Agent tab shows starter screen by default; conversations open as `.fullScreenCover`. Close button (X) warns about unsaved outfits before dismissing. Tab bar hidden during chat (inherent tab-switch protection)
- Outfits generated in chat are ephemeral until user taps "Save Outfit" → SwiftData insert + weather snapshot
- **Agent auto-tagging**: `executeGenerateOutfit` fetches outfit-scoped tags, passes `availableTagNames` to `AnthropicService`, resolves returned tag names to `Tag` objects via `TagManager.resolveTags`
- Style insights appended to `StyleSummary.gapObservations` via `StyleViewModel.appendAgentInsight`
- `OutfitSuggestionDTO.spokenSummary: String?` — conversational voice description generated by Claude, used as Siri's spoken response for AI-generated outfits
- Uses 2048 max tokens

### Weather API
- **Primary**: Apple WeatherKit — requires WeatherKit entitlement
- **Fallback**: Open-Meteo free API (`GET https://api.open-meteo.com/v1/forecast`), no API key needed
- Returns `WeatherSnapshot` (ephemeral) with current conditions + 12-hour forecast
- Location via CoreLocation with "when in use" permission

### API Key
- Read once from `Config.plist` at launch via `ConfigManager`.
- If missing or empty, surface a clear error to the user — do not crash.
- Never hardcode the key. Never log it. Never include it in error messages.

## Naming Conventions
- **Types:** PascalCase (`ClothingItem`, `ScanViewModel`, `AnthropicService`)
- **Properties/methods:** camelCase (`primaryColor`, `analyzeImage()`)
- **Files:** match the primary type they contain (`ClothingItem.swift`, `ScanViewModel.swift`)
- **Constants:** camelCase, not SCREAMING_SNAKE (`maxImageSize`, not `MAX_IMAGE_SIZE`)
- **Booleans:** prefix with `is`, `has`, `can`, `should` (`isLoading`, `hasResults`, `canRetry`)
- **JSON keys from API:** snake_case in JSON, mapped to camelCase via `CodingKeys`

## Common Anti-Patterns — Do NOT Do These
- **No force unwraps** (`!`) on optionals from external data (API responses, plist values, user input).
- **No `print()` for error logging** in production paths. Use structured error handling. `print()` is acceptable only for temporary debugging.
- **No god view models.** If a view model grows beyond ~200 lines, it probably needs to be split.
- **No business logic in views.** If a view has an `if` statement that isn't purely about layout, it belongs in the view model.
- **No raw strings for state.** Use enums for finite states (e.g., `enum ScanState { case idle, loading, success([ClothingItem]), error(String) }`).
- **No nested closures for async work.** Use `async/await`.
- **No editing `.pbxproj` by hand.** File sync handles source files. Build settings go through Xcode's UI or `xcconfig` files.

## Current State (v0.9.2)
- Camera and photo library scanning with Claude vision API for clothing detection, **AI auto-tagging on scan**
- SwiftData persistence for clothing items, scan sessions, outfits, user profile, style summary, and tags
- Images stored on disk (Documents/clothing-images/, Documents/scan-images/, Documents/profile-images/)
- Wardrobe view with grid/list toggle, category filtering, **item tag filter bar (AND multi-select)**, **bulk selection mode** (long-press entry, Edit Tags / Delete), and item detail/edit with AI originals as reference
- Duplicate detection: pre-filter by category+color, Claude-based comparison, user confirmation
- Tab-based navigation: Agent, Wardrobe, Outfits, Profile (Scan merged into Wardrobe — toolbar menu + empty state onboarding)
- **Style Agent chat tab**: starter screen with conversation starters + fullScreenCover chat. **SSE streaming** for token-by-token text display during multi-turn tool_use conversations. Five tools: outfit generation, **outfit editing**, outfit search (intent detection), wardrobe search, and style insight capture. Ephemeral sessions (in-memory only). Inline outfit cards with save action. Weather context chip. Unsaved outfit warning on chat dismiss. Designed for future Siri reuse via stateless `AgentService` (non-streaming path preserved)
- **Conversational outfit editing**: `editOutfit` tool allows users to say "swap the shoes for boots" or "remove the jacket" — fuzzy item matching by type/color, in-place outfit mutation, composition validation warnings
- **Agent intent detection**: system prompt classifies "new/surprise" → generateOutfit, "familiar/go-to" → searchOutfits, "specific items" → searchWardrobe, "modify/swap/add/remove" → editOutfit. `searchOutfits` tool filters saved outfits by tags/query, returns as inline cards
- **Occasion-based outfit filtering** (`OccasionFilter.swift`): hybrid client-side pre-filtering + enhanced AI prompt. `OccasionTier` enum (10 tiers from Casual to White Tie + Gym/Outdoor). Progressive relaxation when filters empty a required category. Wardrobe gap notes with investment suggestions. Style weight scaling by occasion (HIGH casual → LOW formal). Dress code instructions and priority hierarchies per tier. Used by OutfitViewModel, AgentViewModel, and SiriOutfitService
- Outfit generation: manual creation via item picker, AI-powered with occasion/season/weather context, **occasion-based item filtering**, deduplication, item match validation, **wardrobe gap notes**
- Outfit display: layer-ordered cards (Outerwear → Full Body → Top → Bottom → Footwear → Accessory), favorites, AI reasoning
- **Scoped tagging system**: `Tag` SwiftData model with `TagScope` (.outfit, .item) for separate tag pools. `scopeRaw` stored property, enforced uniqueness by name+scope in code via `TagManager`. **Outfit tags**: 12 predefined (seasonal, occasion, `siri`), custom user tags, AI auto-tagging. **Item tags**: 8 predefined (seasonal overlap + everyday, statement, layering, seasonal-rotate), custom user tags, AI auto-tagging on scan. Tag chips, filter bars, picker sheets, and bulk edit all scope-aware
- Tag management in Profile settings: sections for Outfit Tags and Item Tags, each with predefined/custom subsections, CRUD via `TagManager`
- **Item tagging**: tag section in ItemDetailView (chips + edit via TagPickerSheet), tag section in AddItemView, bulk item tagging in WardrobeView
- **Outfit editing**: inline edit mode in OutfitDetailView — edit name, occasion, items, and tags. Local `@State` copies with Cancel/Done. Add items via `OutfitEditItemPicker`, remove via inline minus button. Advisory composition warnings via `OutfitLayerOrder.warnings()` (multiple footwear, full-body + top/bottom conflicts). Tags edited via `TagPickerSheet` binding, changes applied only on save
- Manual item entry form with all attributes, optional photo, and tag selection
- Weather integration: WeatherKit + Open-Meteo fallback, toolbar indicator, detail sheet with hourly forecast, weather context in AI prompts, weather override toggle
- Location: CoreLocation for weather, reverse geocoding for display, custom location override with geocoding
- Profile: name, photo, temperature unit (°C/°F), theme (System/Light/Dark) with full dark mode, location override, tag management
- Style & Comfort questionnaire: cold/heat sensitivity, layering preference, style identity, comfort vs appearance, weather dressing approach — stored on `UserProfile` with enum bridges
- Template-based style summary via `StyleSummaryTemplate` (deterministic, no LLM), with manual edit support
- AI style analysis: sends wardrobe + outfits to Claude, returns style modes/identity/gaps/weather behavior. Auto-triggers on data changes, merges incrementally into `StyleSummary`. Agent insights appended via `appendAgentInsight`
- Enriched style profile display with mode cards, color swatches, seasonal patterns, gap observations
- Comfort-aware and style-aware outfit generation using user preferences and AI-enriched summary
- Wardrobe analytics: Swift Charts — category bar chart, formality donut chart, color distribution grid
- Brand design system: adaptive `Theme.swift` with Champagne accent, warm dark mode palette, reusable modifiers and button styles
- Error handling: missing key, network, API, empty results, insufficient wardrobe
- **Siri & HomePod integration** via App Intents framework (in-app, no extension target):
  - **"What should I wear today?"** — weather + preferences + wardrobe → outfit → spoken response
  - **"What should I wear to [occasion]?"** — occasion-constrained (`OutfitOccasion` AppEnum: casual, date night, work, formal, cocktail, black tie, gym, travel, outdoor) → spoken response
  - **Siri outfit selection**: queries outfits tagged "siri", filters by season/weather/occasion, picks randomly from matching pool
  - **AI generation fallback**: toggled off by default in Profile settings. When enabled and no siri-tagged outfits match, generates via `AnthropicService` and auto-saves with "siri" tag (grows pool over time)
  - **Template-based spoken summaries** for tagged outfits (instant, no API call). AI-generated outfits use `spokenSummary` from DTO
  - `SiriOutfitService` encapsulates selection algorithm; `StyleContextHelper` shared across Agent/Outfit/Siri contexts
  - `ModelContainer` registered via `AppDependencyManager` for App Intent dependency injection
  - HomePod triggers via Siri intent forwarding to iPhone

## Data Model Design

```
ClothingItem (SwiftData @Model)
├── id: UUID
├── type, category, primaryColor, secondaryColor, pattern
├── fabricEstimate, weight, formality, season, fit, statementLevel
├── itemDescription: String       # renamed from "description" (NSObject conflict)
├── brand: String?, notes: String?
├── imagePath: String?, sourceImagePath: String?
├── aiOriginalValues: String?     # JSON blob of original AI-detected values
├── createdAt: Date, updatedAt: Date
├── scanSession: ScanSession?
├── outfits: [Outfit]
└── tags: [Tag]                  # @Relationship — many-to-many via Tag model (item scope)

ScanSession (SwiftData @Model)
├── id: UUID, imagePath: String, date: Date
└── items: [ClothingItem]         # @Relationship(deleteRule: .nullify)

Outfit (SwiftData @Model)
├── id: UUID
├── name: String?, occasion: String?, reasoning: String?
├── isAIGenerated: Bool, isFavorite: Bool, createdAt: Date
├── wardrobeGaps: String?         # JSON-encoded [String] — wardrobe gap notes/suggestions
├── items: [ClothingItem]         # @Relationship(deleteRule: .nullify)
├── tags: [Tag]                   # @Relationship — many-to-many via Tag model
├── displayName: String           # computed: name → occasion → formatted date
├── wardrobeGapsDecoded: [String] # computed: decodes wardrobeGaps JSON or returns []
├── weatherTempAtCreation: Double?, weatherFeelsLikeAtCreation: Double?
├── seasonAtCreation: String?, monthAtCreation: Int?
├── lastSuggestedBySiriAt: Date?   # auto-updated when Siri suggests this outfit
└── (weather fields captured at creation/favorite, backfilled if missing)

UserProfile (SwiftData @Model)
├── id: UUID, name: String, profileImagePath: String?
├── temperatureUnitRaw: String, themePreferenceRaw: String
├── isLocationOverrideEnabled: Bool
├── locationOverrideName: String?, locationOverrideLat/Lon: Double?
├── createdAt: Date, updatedAt: Date
├── coldSensitivity, heatSensitivity: String?
├── bodyTempNotes, layeringPreference: String?
├── selectedStyles: String?       # JSON array of style labels
├── comfortVsAppearance: String?, weatherDressingApproach: String?
├── isSiriAIGenerationEnabled: Bool  # default false, controls Siri AI fallback
└── (all questionnaire fields have enum bridges on the model)

StyleSummary (SwiftData @Model)
├── id: UUID
├── overallIdentity: String, styleModes: String? (JSON array)
├── temporalNotes, gapObservations, weatherBehavior: String?
├── lastAnalyzedAt: Date, analysisVersion: Int
├── itemCountAtLastAnalysis, outfitCountAtLastAnalysis, favoritedOutfitCountAtLastAnalysis: Int
├── isUserEdited: Bool, isAIEnriched: Bool
└── createdAt: Date

Tag (SwiftData @Model)
├── id: UUID
├── name: String                  # normalized: lowercased, trimmed; unique per (name+scope)
├── isPredefined: Bool            # true for system tags (cannot be deleted)
├── colorHex: String?             # optional hex color for UI chip display
├── scopeRaw: String              # "outfit" or "item" — TagScope enum bridge
├── createdAt: Date
├── outfits: [Outfit]             # @Relationship — inverse of Outfit.tags (outfit scope)
└── items: [ClothingItem]         # @Relationship — inverse of ClothingItem.tags (item scope)
```

## Roadmap

### v0.8 — Item Tagging & Agent Intent Detection ✅

#### Scoped Tag System
- `TagScope` enum (.outfit, .item) with `scopeRaw` stored property on `Tag` — separate tag pools, same model
- **Outfit predefined tags** (12): spring, summer, fall, winter, work, casual, date-night, formal, gym, travel, outdoor, siri
- **Item predefined tags** (8): spring, summer, fall, winter, everyday, statement, layering, seasonal-rotate
- `TagManager` helper: shared CRUD (create, rename, delete, updateColor, resolveTags) with name+scope uniqueness
- `TagSeeder` seeds both pools idempotently

#### Item Tagging
- `ClothingItem.tags: [Tag]` many-to-many relationship (item scope)
- `ClothingItemDTO.tags: [String]` with resilient decoder
- Tag section in `ItemDetailView` (chips + TagPickerSheet) and `AddItemView`
- `TagFilterBar` in Wardrobe tab (AND multi-select, item scope)
- Bulk item tagging in Wardrobe tab (long-press → select → Edit Tags / Delete)
- AI auto-tagging on scan: `AnthropicService.analyzeClothing` injects available item tag names, `ScanViewModel` resolves via `TagManager.resolveTags`

#### Scope-Aware UI
- `TagFilterBar`, `TagPickerSheet`, `BulkTagEditSheet`, `TagManagementView` all accept `scope: TagScope` parameter
- `TagManagementView` shows sections by scope: "Outfit Tags" / "Item Tags", each with Predefined + Custom
- **Hit-testing rule**: never wrap `TagChipView` inside a `Button` in List rows — use `.contentShape(Rectangle())` + `.onTapGesture` instead
- `PickerGridCell` is `internal` — reusable across picker contexts

#### Agent Intent Detection
- `searchOutfits(query?, tags?)` tool added — filters saved outfits by tag names and/or query text, sorts favorites first, returns top 5 as inline outfit cards
- System prompt INTENT DETECTION rules: NEW/DIFFERENT/SURPRISE → `generateOutfit`, FAMILIAR/GO-TO/WORN BEFORE → `searchOutfits`, SPECIFIC ITEMS → `searchWardrobe`, AMBIGUOUS → `generateOutfit`
- Outfit overview (count + favorites) added to system prompt
- If `searchOutfits` returns nothing, agent suggests generating a new outfit

### v0.9 — Siri & HomePod Integration ✅

#### App Intents (In-App, No Extension)
- **In-app App Intents** — runs in main app process (system launches app in background), no app group or shared container needed
- `ModelContainer` explicitly created in `AttirelyApp.init()` and registered via `AppDependencyManager.shared.add(dependency:)` for intent dependency injection
- `WhatToWearTodayIntent` — "What should I wear today?" with weather + preferences context
- `WhatToWearToIntent` — "What should I wear to [occasion]?" with `OutfitOccasion` AppEnum (casual, date night, work, formal, gym, travel, outdoor)
- `AttirelyShortcuts` — AppShortcutsProvider with natural Siri phrases for both intents
- Single-turn only — no back-and-forth dialog flows
- HomePod triggers via Siri intent forwarding to iPhone

#### Siri Outfit Selection (`SiriOutfitService`)
- Queries outfits tagged `"siri"`, filtered by current weather/season/occasion, **random selection** from matching pool
- Season filtering: checks `seasonAtCreation` and seasonal tags against current weather-adapted season
- Weather filtering: outfits within ±10°C of current temperature pass; outfits without weather data always pass
- Occasion filtering: fuzzy match on outfit `occasion` field and tags; relaxes if filter eliminates all candidates
- `lastSuggestedBySiriAt: Date?` tracked on `Outfit` for analytics (does not influence selection)
- **Template-based spoken summaries** for pre-tagged outfits: "How about [name]? It's your [color] [type], [color] [type], and [color] [type]." — instant, no API call
- **AI generation fallback**: `isSiriAIGenerationEnabled` on `UserProfile` (default false). When enabled + no match, calls `AnthropicService.generateOutfits()`, auto-saves with "siri" tag, uses `spokenSummary` from DTO
- If AI generation disabled and no siri-tagged outfits, prompts user to tag outfits or enable AI generation
- Weather: uses profile location override if set, else `LocationService`, falls back to `SeasonHelper.currentSeason()` if unavailable

#### Shared Context Helper (`StyleContextHelper`)
- Extracted from `AgentViewModel` and `OutfitViewModel` to eliminate duplication
- `comfortPreferencesString(from:)`, `styleContextString(from:)`, `weatherContextString(from:)` — used by Agent, Outfit, and Siri flows

#### Siri Settings (Profile)
- Toggle for "AI outfit generation" under new "Siri" section in Profile preferences
- Warning text when enabled: explains 5–15s delay
- Help text: suggests tagging outfits with "siri" for instant responses

### v0.9.1 — Occasion-Based Outfit Filtering ✅

#### Hybrid Filtering System (`OccasionFilter.swift`)
- `OccasionTier` enum: 10 tiers — Casual, Smart Casual, Business Casual, Business, Cocktail, Formal, Black Tie, White Tie, Gym/Athletic, Outdoor/Active
- Client-side hard-exclude filtering by formality level, type keywords (substring match on `item.type`), and fabric
- Gym/Athletic uses inverted logic: items must match athletic keywords OR be casual Top/Bottom
- **Progressive relaxation**: if all items in a required category (Top, Bottom, Footwear) are filtered out, all original items for that category are restored
- Small wardrobes (< 5 items) skip filtering entirely
- `OccasionTier.pickerGroups` provides grouped picker structure (Everyday, Work, Dress Code, Active)
- `OccasionTier(fromString:)` maps free-form strings (agent tool calls) via keyword matching

#### Wardrobe Gap Notes
- `WardrobeGap` struct: category, description, investment suggestion — generated when filters relax
- Context-aware suggestions vary by category × occasion (e.g., Footwear for Black Tie → "patent leather oxfords")
- Client-side gaps merged with AI-returned `wardrobe_gaps` via `OccasionFilter.mergeGaps()`
- Persisted on `Outfit.wardrobeGaps: String?` (JSON-encoded `[String]`), decoded via `wardrobeGapsDecoded`
- Displayed in OutfitDetailView (card with warning icon) and AgentMessageBubble (inline lightbulb notes)

#### Enhanced Outfit Generation Prompt
- `OccasionFilterContext` passed to `AnthropicService.generateOutfits` with tier, style weight, gaps, relaxed categories
- Dress code instructions injected per occasion tier (e.g., Black Tie strict rules, Gym function-first)
- Style weight scaling: HIGH (casual) → MEDIUM (business) → LOW (formal/activity) — controls style profile influence
- Priority hierarchy shifts by occasion (casual: aesthetics first; formal: dress code compliance first)
- `OutfitSuggestionDTO.wardrobeGaps: [String]` — AI returns investment suggestions (resilient decoder)

#### Expanded Occasion Options
- `OutfitGenerationContextSheet` uses grouped `OccasionTier` picker (replaces flat string array)
- `OutfitViewModel.selectedOccasionTier: OccasionTier?` replaces `selectedOccasion: String?`
- `AgentService` tool description updated with expanded occasion list
- `OutfitOccasion` AppEnum (Siri): added `cocktail` and `blackTie` cases with `occasionTier` computed property

### v0.9.2 — Agent Streaming, Outfit Editing, Chat Dismissal ✅

#### SSE Streaming
- Token-by-token text streaming via Anthropic SSE API (`"stream": true`)
- `SSEStreamParser` parses `URLSession.AsyncBytes` into typed `SSEEvent` values via `AsyncThrowingStream`
- `ContentBlockAccumulator` reconstructs full response (text parts + tool calls + raw assistant content) from streamed events
- `AgentService.streamMessage()` wraps streaming transport (stateless); existing `sendMessage()` preserved for Siri
- `AnthropicService.streamAgentRequest()` handles `URLSession.bytes(for:)` + HTTP error extraction from byte stream
- `AgentViewModel.runConversationLoop` rewritten: streams text deltas → immediate UI update, accumulates tool_use blocks silently, executes tools between streaming turns
- `appendTextToStreamingMessage()` hides dots on first token, appends subsequent tokens
- `Task` cancellation support: `currentTask` property on ViewModel, `cancelCurrentTask()` for mid-stream abort

#### Conversational Outfit Editing
- New `editOutfit` tool (5th agent tool): `outfit_name`, `remove_items?`, `add_items?`, `new_name?`, `new_occasion?`
- `EditOutfitInput` struct in `AgentToolDTO.swift` for typed parsing
- Fuzzy item matching via `matchItem(description:in:)` — word overlap scoring against type/color/category/fabric
- `resolveOutfit(named:)` finds target outfit from conversation messages (fuzzy name match, fallback to most recent unsaved)
- In-place `Outfit` mutation (reference type) with forced `ChatMessage` array reassignment to trigger `@Observable` re-render
- Composition validation via `OutfitLayerOrder.warnings()` included in tool result text
- System prompt INTENT DETECTION updated: "modify/swap/add/remove" → `editOutfit`

#### Chat as Dismissible Full-Screen Cover
- Agent tab shows starter screen by default (weather chip, title, description, starter buttons, input bar)
- Starting a conversation (starter button or input bar) opens `.fullScreenCover` with chat UI
- Close button (X) in chat toolbar — warns about unsaved outfits via `.confirmationDialog` before dismissing
- `hasUnsavedOutfits` computed property: checks `outfit.modelContext == nil` across all conversation outfits
- `dismissChat()` cancels in-flight streaming, clears conversation, dismisses cover
- Tab bar hidden while chat is open (inherent fullScreenCover behavior) — provides tab-switch protection

### v0.10 — Image Extraction & Confidence
- Crop/extract individual items from group photos into per-item images
- Background removal via Apple Vision framework (`VNGenerateForegroundInstanceMaskRequest`)
- Attribute confidence system: Claude returns per-attribute confidence (`observed`/`inferred`/`assumed`), stored in `attributeConfidence: String?` on `ClothingItem`
- Surface confidence to user: subtle indicator on inferred/assumed attributes, badge for mostly low-confidence items
- Re-scan merge workflow: user adds better photo, system re-runs and merges (user edits preserved, AI fields updated)
- New field: `cutoutImagePath: String?` on `ClothingItem`

### v0.11 — Visual Outfit Compositor
- Replace card-based outfit layout with layered visual composition (items stacked as worn on a body)
- Two sub-problems: isolation (clean cutouts) and normalization (consistent perspective/scale/lighting across different source photos)
- Planned approach: generative AI to transform source photos into standardized flat-lay product images, then composite via category-based anchor points and z-ordering
- New field: `flatLayImagePath: String?` on `ClothingItem`

### Future Ideas
- iCloud sync via SwiftData + CloudKit
- Outfit calendar (what you wore when)
- Share outfits
- Seasonal wardrobe rotation suggestions
- Virtual try-on (pose estimation + outfit overlay)

