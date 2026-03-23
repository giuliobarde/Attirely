# Attirely — Project Guide

## What is Attirely?
A wardrobe management iOS app. Users scan clothing via camera/photo library, the app identifies items using Claude's vision API, and builds a persistent digital wardrobe. Users can generate outfits manually or with AI assistance.

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
│   ├── ClothingItemDTO.swift       # Codable struct (API parsing)
│   ├── ScanSession.swift           # SwiftData @Model
│   ├── Outfit.swift                # SwiftData @Model (outfit collection + weather snapshot)
│   ├── OutfitSuggestionDTO.swift   # Codable struct (AI outfit parsing)
│   ├── StyleAnalysisDTO.swift      # Codable structs (AI style analysis parsing)
│   ├── WeatherData.swift           # Ephemeral structs (current + hourly weather)
│   ├── UserProfile.swift           # SwiftData @Model (user prefs, profile, style questionnaire)
│   └── StyleSummary.swift          # SwiftData @Model (template/AI style summary)
├── Services/
│   ├── AnthropicService.swift      # Claude API calls (scan, duplicates, outfits, style analysis)
│   ├── ConfigManager.swift         # Reads API key from Config.plist
│   ├── ImageStorageService.swift   # Save/load images on disk
│   ├── LocationService.swift       # CoreLocation wrapper for user location
│   └── WeatherService.swift        # WeatherKit + Open-Meteo fallback
├── ViewModels/
│   ├── ScanViewModel.swift
│   ├── WardrobeViewModel.swift
│   ├── OutfitViewModel.swift       # Outfit creation, generation, favorites
│   ├── WeatherViewModel.swift      # Weather state, location, fetch coordination
│   ├── ProfileViewModel.swift      # Profile state, analytics, geocoding
│   └── StyleViewModel.swift        # AI style analysis state, debounce, merge
├── Views/
│   ├── MainTabView.swift           # TabView (Scan + Outfits + Wardrobe + Profile)
│   ├── HomeView.swift
│   ├── ResultsView.swift
│   ├── ClothingItemCard.swift
│   ├── ImagePicker.swift           # UIImagePickerController wrapper
│   ├── WardrobeView.swift          # Browsable wardrobe (grid/list)
│   ├── ItemDetailView.swift        # View/edit item details
│   ├── DuplicateWarningBanner.swift
│   ├── DuplicateReviewSheet.swift
│   ├── OutfitsView.swift           # Outfit list with favorites filter
│   ├── OutfitDetailView.swift      # Layer-ordered card stack view
│   ├── OutfitRowCard.swift         # Compact outfit card for list
│   ├── OutfitGenerationContextSheet.swift  # AI generation context picker
│   ├── ItemPickerSheet.swift       # Manual outfit item selection
│   ├── AddItemView.swift           # Manual wardrobe item entry form
│   ├── WeatherWidgetView.swift     # Compact toolbar weather indicator
│   ├── WeatherDetailSheet.swift    # Full weather modal with hourly forecast
│   ├── ProfileView.swift           # Profile tab (details, prefs, analytics)
│   └── WardrobeAnalyticsView.swift # Swift Charts wardrobe analytics
├── Helpers/
│   ├── Theme.swift                 # Brand design system: color tokens, ViewModifiers, ButtonStyles
│   ├── ColorMapping.swift          # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   ├── OutfitLayerOrder.swift      # Category → layer sort order
│   ├── SeasonHelper.swift          # Season detection from date/weather
│   ├── TemperatureFormatter.swift  # °C/°F formatting helper
│   └── StyleSummaryTemplate.swift  # Deterministic style summary from questionnaire
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
- `ClothingItem` is a SwiftData `@Model` class for persistence. `ClothingItemDTO` is a `Codable` struct for API parsing. `ScanSession`, `Outfit`, `UserProfile`, and `StyleSummary` are SwiftData `@Model`s. `OutfitSuggestionDTO` and `StyleAnalysisDTO` are `Codable` structs for AI response parsing.
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
- Text-only request — sends wardrobe item attributes with UUIDs
- Generates exactly 1 outfit per request; returns `OutfitSuggestionDTO` with `name`, `occasion`, `item_ids`, `reasoning`
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

## Current State (v0.5c)
- Camera and photo library scanning with Claude vision API for clothing detection
- SwiftData persistence for clothing items, scan sessions, outfits, user profile, and style summary
- Images stored on disk (Documents/clothing-images/, Documents/scan-images/, Documents/profile-images/)
- Wardrobe view with grid/list toggle, category filtering, and item detail/edit with AI originals as reference
- Duplicate detection: pre-filter by category+color, Claude-based comparison, user confirmation
- Tab-based navigation: Scan, Outfits, Wardrobe, Profile
- Outfit generation: manual creation via item picker, AI-powered with occasion/season/weather context, deduplication, item match validation
- Outfit display: layer-ordered cards (Outerwear → Full Body → Top → Bottom → Footwear → Accessory), favorites, AI reasoning
- Manual item entry form with all attributes and optional photo
- Weather integration: WeatherKit + Open-Meteo fallback, toolbar indicator, detail sheet with hourly forecast, weather context in AI prompts, weather override toggle
- Location: CoreLocation for weather, reverse geocoding for display, custom location override with geocoding
- Profile: name, photo, temperature unit (°C/°F), theme (System/Light/Dark) with full dark mode, location override
- Style & Comfort questionnaire: cold/heat sensitivity, layering preference, style identity, comfort vs appearance, weather dressing approach — stored on `UserProfile` with enum bridges
- Template-based style summary via `StyleSummaryTemplate` (deterministic, no LLM), with manual edit support
- AI style analysis: sends wardrobe + outfits to Claude, returns style modes/identity/gaps/weather behavior. Auto-triggers on data changes, merges incrementally into `StyleSummary`
- Enriched style profile display with mode cards, color swatches, seasonal patterns, gap observations
- Comfort-aware and style-aware outfit generation using user preferences and AI-enriched summary
- Wardrobe analytics: Swift Charts — category bar chart, formality donut chart, color distribution grid
- Brand design system: adaptive `Theme.swift` with Champagne accent, warm dark mode palette, reusable modifiers and button styles
- Error handling: missing key, network, API, empty results, insufficient wardrobe

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
└── outfits: [Outfit]

ScanSession (SwiftData @Model)
├── id: UUID, imagePath: String, date: Date
└── items: [ClothingItem]         # @Relationship(deleteRule: .nullify)

Outfit (SwiftData @Model)
├── id: UUID
├── name: String?, occasion: String?, reasoning: String?
├── isAIGenerated: Bool, isFavorite: Bool, createdAt: Date
├── items: [ClothingItem]         # @Relationship(deleteRule: .nullify)
├── displayName: String           # computed: name → occasion → formatted date
├── weatherTempAtCreation: Double?, weatherFeelsLikeAtCreation: Double?
├── seasonAtCreation: String?, monthAtCreation: Int?
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
└── (all questionnaire fields have enum bridges on the model)

StyleSummary (SwiftData @Model)
├── id: UUID
├── overallIdentity: String, styleModes: String? (JSON array)
├── temporalNotes, gapObservations, weatherBehavior: String?
├── lastAnalyzedAt: Date, analysisVersion: Int
├── itemCountAtLastAnalysis, outfitCountAtLastAnalysis, favoritedOutfitCountAtLastAnalysis: Int
├── isUserEdited: Bool, isAIEnriched: Bool
└── createdAt: Date
```

## Roadmap

### v0.6 — Style Agent (Chat)
- New **Agent tab** (tab order: Agent | Scan | Outfits | Wardrobe | Profile) with a conversational chat interface
- Multi-turn conversation with Claude for style discussion, outfit generation, and wardrobe exploration
- **Ephemeral sessions** — conversation history lives in-memory only (`AgentViewModel`), no persistence
- **Shared generation core** — `AgentService` (UI-agnostic) accepts structured input (wardrobe, weather, preferences, user intent) and returns structured output. Both chat UI and future Siri surface use the same engine
- Generation core supports **single-turn mode** (one request → one response, for Siri later) and **multi-turn mode** (ongoing conversation with message history)

#### Agent Tools (Claude tool_use)
The agent has tools it can invoke mid-conversation:
- `generateOutfit(occasion?, constraints?)` — generates an outfit from the user's wardrobe; weather is always fetched fresh and required
- `searchWardrobe(query)` — finds specific items matching a description/criteria
- `updateStyleInsight(insight, confidence)` — captures durable style preference signals ("leaning minimalist", "never wears yellow") to queue for `StyleSummary` updates
- Additional tools may be added as needed

#### Context Injection Strategy
- **Always injected** (system prompt): weather snapshot, comfort preferences, style summary, wardrobe stats
- **Loaded on demand** (via tool use): full wardrobe items (when generating/searching), recent outfits (for dedup)
- **Compact format** for wardrobe in context: one-line-per-item (`"ID | Navy Blazer | Outerwear/Jacket | Navy/None | Wool | Semi-Formal | Fall,Winter"`) to manage token budget

#### Style Insight Extraction
- Instead of storing chats, extract **deltas from baseline** — events that vary from the user's established preferences
- Inline via `updateStyleInsight` tool use: Claude detects meaningful preference signals mid-conversation and calls the tool
- Surface a subtle confirmation in chat ("Noted — you're leaning minimalist lately")
- Insights accumulate and fold into the next `StyleSummary` analysis rather than directly rewriting fields

#### Chat UI
- Standard chat interface with messages list and text input
- **Outfit cards inline** — reuse `OutfitRowCard` embedded in chat flow when the agent generates an outfit
- **Save action** — inline "Save to Outfits" button on generated outfits (ephemeral chat, durable outfit)
- **Item references** — tappable clothing item mentions linking to `ItemDetailView`
- **Weather context** — subtle header/chip showing current weather the agent is working with
- **Conversation starters** — empty state with suggested prompts ("What should I wear today?", "Help me plan outfits for a trip", "What's missing from my wardrobe?")

#### New Files
- `Models/ChatMessage.swift` — ephemeral struct for conversation messages (role, content, optional tool results)
- `Models/AgentToolDTO.swift` — Codable structs for agent tool use requests/responses
- `Services/AgentService.swift` — UI-agnostic generation core, multi-turn Claude API interaction with tool definitions
- `ViewModels/AgentViewModel.swift` — conversation state, message history, tool result handling
- `Views/AgentView.swift` — chat interface
- `Views/AgentMessageBubble.swift` — individual message rendering (text, outfit cards, insight confirmations)

#### Response Format
- `OutfitSuggestionDTO` extended with `spokenSummary: String?` — 1-2 sentence natural-speech description of the outfit, generated alongside `reasoning`. Costs minimal tokens, prepares for Siri voice output

### v0.7 — Siri & HomePod Integration
- **App Intents** framework (iOS 16+) wrapping the same `AgentService` generation core
- Two intents:
  - **"What should I wear today?"** — weather + preferences + wardrobe → outfit → spoken response
  - **"What should I wear to [occasion]?"** — occasion-constrained generation → spoken response
- Single-turn mode only — no back-and-forth dialog flows for v1
- Uses `spokenSummary` from outfit generation as Siri's voice response
- Weather is mandatory; falls back to seasonal defaults if unavailable
- Accesses SwiftData store from App Intent extension process
- HomePod triggers via Siri intent forwarding to iPhone

#### Siri-Specific Considerations
- **Latency** — consider pre-generating a "daily suggestion" on app open that Siri can read back instantly, with on-demand generation as fallback
- **Lean context** — single-turn loads everything at once (no progressive loading like chat), so compact wardrobe format is critical
- **Graceful degradation** — if weather unavailable, fall back to seasonal defaults based on date rather than failing

### v0.8 — Image Extraction & Confidence
- Crop/extract individual items from group photos into per-item images
- Background removal via Apple Vision framework (`VNGenerateForegroundInstanceMaskRequest`)
- Attribute confidence system: Claude returns per-attribute confidence (`observed`/`inferred`/`assumed`), stored in `attributeConfidence: String?` on `ClothingItem`
- Surface confidence to user: subtle indicator on inferred/assumed attributes, badge for mostly low-confidence items
- Re-scan merge workflow: user adds better photo, system re-runs and merges (user edits preserved, AI fields updated)
- New field: `cutoutImagePath: String?` on `ClothingItem`

### v0.9 — Visual Outfit Compositor
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
