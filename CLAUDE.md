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
│   ├── ClothingItemDTO.swift       # Codable struct (API parsing)
│   ├── ScanSession.swift           # SwiftData @Model
│   ├── Outfit.swift                # SwiftData @Model (outfit collection + weather snapshot)
│   ├── OutfitSuggestionDTO.swift   # Codable struct (AI outfit parsing, + spokenSummary)
│   ├── StyleAnalysisDTO.swift      # Codable structs (AI style analysis parsing)
│   ├── ChatMessage.swift           # Ephemeral struct (agent chat messages, no persistence)
│   ├── AgentToolDTO.swift          # Tool call/result types for agent tool_use
│   ├── WeatherData.swift           # Ephemeral structs (current + hourly weather)
│   ├── UserProfile.swift           # SwiftData @Model (user prefs, profile, style questionnaire)
│   ├── StyleSummary.swift          # SwiftData @Model (template/AI style summary)
│   └── Tag.swift                   # SwiftData @Model (shared tagging: outfits now, items later)
├── Services/
│   ├── AnthropicService.swift      # Claude API calls (scan, duplicates, outfits, style analysis, agent)
│   ├── AgentService.swift          # Stateless agent conversation service (tool_use, multi-turn)
│   ├── ConfigManager.swift         # Reads API key from Config.plist
│   ├── ImageStorageService.swift   # Save/load images on disk
│   ├── LocationService.swift       # CoreLocation wrapper for user location
│   └── WeatherService.swift        # WeatherKit + Open-Meteo fallback
├── ViewModels/
│   ├── ScanViewModel.swift
│   ├── WardrobeViewModel.swift
│   ├── OutfitViewModel.swift       # Outfit creation, generation, favorites
│   ├── AgentViewModel.swift        # Chat agent conversation state, tool-use loop, context building
│   ├── WeatherViewModel.swift      # Weather state, location, fetch coordination
│   ├── ProfileViewModel.swift      # Profile state, analytics, geocoding
│   └── StyleViewModel.swift        # AI style analysis state, debounce, merge, agent insights
├── Views/
│   ├── MainTabView.swift           # TabView (Agent + Wardrobe + Outfits + Profile)
│   ├── ResultsView.swift
│   ├── ClothingItemCard.swift
│   ├── ImagePicker.swift           # UIImagePickerController wrapper
│   ├── WardrobeView.swift          # Browsable wardrobe (grid/list) + scan integration (camera/photo/manual)
│   ├── ItemDetailView.swift        # View/edit item details
│   ├── DuplicateWarningBanner.swift
│   ├── DuplicateReviewSheet.swift
│   ├── OutfitsView.swift           # Outfit list with favorites filter
│   ├── OutfitDetailView.swift      # Layer-ordered card stack view with inline edit mode
│   ├── OutfitRowCard.swift         # Compact outfit card for list
│   ├── OutfitGenerationContextSheet.swift  # AI generation context picker
│   ├── ItemPickerSheet.swift       # Manual outfit item selection
│   ├── AddItemView.swift           # Manual wardrobe item entry form
│   ├── WeatherWidgetView.swift     # Compact toolbar weather indicator
│   ├── WeatherDetailSheet.swift    # Full weather modal with hourly forecast
│   ├── AgentView.swift             # Chat agent tab (messages, input, starters, weather chip)
│   ├── AgentMessageBubble.swift    # Agent message rendering (text, outfit cards, item refs, insights)
│   ├── ProfileView.swift           # Profile tab (details, prefs, analytics)
│   ├── WardrobeAnalyticsView.swift # Swift Charts wardrobe analytics
│   ├── TagChipView.swift           # Reusable tag chip component (selected/default states, custom colors)
│   ├── TagFilterBar.swift          # Horizontal scrolling tag filter in Outfits tab
│   ├── TagPickerSheet.swift        # Toggle/create tags via Binding (reusable for outfits + future items)
│   ├── TagManagementView.swift     # Full tag CRUD screen (Profile → Manage Tags)
│   ├── BulkTagEditSheet.swift      # Bulk tag editor with mixed-state logic (checked/unchecked/mixed)
│   └── OutfitEditItemPicker.swift  # Item picker for outfit editing (add items to existing outfit)
├── Helpers/
│   ├── Theme.swift                 # Brand design system: color tokens, ViewModifiers, ButtonStyles
│   ├── ColorMapping.swift          # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   ├── OutfitLayerOrder.swift      # Category → layer sort order + composition warnings
│   ├── SeasonHelper.swift          # Season detection from date/weather
│   ├── TemperatureFormatter.swift  # °C/°F formatting helper
│   ├── StyleSummaryTemplate.swift  # Deterministic style summary from questionnaire
│   └── TagSeeder.swift             # Idempotent predefined tag seeding on launch
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
- `ClothingItem` is a SwiftData `@Model` class for persistence. `ClothingItemDTO` is a `Codable` struct for API parsing. `ScanSession`, `Outfit`, `UserProfile`, `StyleSummary`, and `Tag` are SwiftData `@Model`s. `OutfitSuggestionDTO` (includes `tags: [String]` with resilient decoder) and `StyleAnalysisDTO` are `Codable` structs for AI response parsing.
- `ChatMessage` is an ephemeral in-memory struct (no SwiftData) for agent conversation messages. `AgentToolDTO.swift` contains `ToolUseBlock`, `AgentTurn`, and typed tool input structs for Claude tool_use parsing.
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
- Generates exactly 1 outfit per request; returns `OutfitSuggestionDTO` with `name`, `occasion`, `item_ids`, `reasoning`, `tags`
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
- Multi-turn conversation via `AgentService.sendMessage()` — stateless, one API call per invocation
- Uses `system` top-level key for persistent context injection (weather, comfort preferences, style summary, wardrobe category counts)
- Claude `tool_use` with three tools: `generateOutfit(occasion?, constraints?)`, `searchWardrobe(query)`, `updateStyleInsight(insight, confidence)`
- Tool-use loop in `AgentViewModel` (max 5 iterations), not in service — enables future Siri single-turn reuse
- Full wardrobe items loaded on-demand via tool execution, not in system prompt (token budget)
- `AnthropicService.sendAgentRequest` returns full JSON dict (handles tool_use + text content blocks)
- Outfits generated in chat are ephemeral until user taps "Save Outfit" → SwiftData insert + weather snapshot
- **Agent auto-tagging**: `executeGenerateOutfit` fetches all tags, passes `availableTagNames` to `AnthropicService`, resolves returned tag names to `Tag` objects on created outfits
- Style insights appended to `StyleSummary.gapObservations` via `StyleViewModel.appendAgentInsight`
- `OutfitSuggestionDTO.spokenSummary: String?` prepares for Siri voice output (v0.9)
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

## Current State (v0.7)
- Camera and photo library scanning with Claude vision API for clothing detection
- SwiftData persistence for clothing items, scan sessions, outfits, user profile, style summary, and tags
- Images stored on disk (Documents/clothing-images/, Documents/scan-images/, Documents/profile-images/)
- Wardrobe view with grid/list toggle, category filtering, and item detail/edit with AI originals as reference
- Duplicate detection: pre-filter by category+color, Claude-based comparison, user confirmation
- Tab-based navigation: Agent, Wardrobe, Outfits, Profile (Scan merged into Wardrobe — toolbar menu + empty state onboarding)
- **Style Agent chat tab**: multi-turn conversation with Claude using tool_use for outfit generation, wardrobe search, and style insight capture. Ephemeral sessions (in-memory only). Inline outfit cards with save action. Weather context chip. Conversation starters. Designed for future Siri reuse via stateless `AgentService`
- Outfit generation: manual creation via item picker, AI-powered with occasion/season/weather context, deduplication, item match validation
- Outfit display: layer-ordered cards (Outerwear → Full Body → Top → Bottom → Footwear → Accessory), favorites, AI reasoning
- **Outfit tagging system**: shared `Tag` SwiftData model (many-to-many with `Outfit`). 12 predefined tags (seasonal, occasion, `siri`), custom user tags. AI auto-tagging on outfit generation (both direct and agent). Tag chips on outfit cards and detail view. Tag filter bar in Outfits tab (AND multi-select). Tag picker sheet for editing (uses `@Binding var selectedTags`). Bulk-tag selection mode with long-press entry, unified Edit Tags sheet with mixed-state indicators, bulk delete with confirmation. Tag management in Profile settings (create/rename/delete custom tags, color picker). `Color(hex:)` and `Color.toHex()` extensions for tag chip colors. Improved tag chip contrast (~4.5:1 WCAG)
- **Outfit editing**: inline edit mode in OutfitDetailView — edit name, occasion, items, and tags. Local `@State` copies with Cancel/Done. Add items via `OutfitEditItemPicker`, remove via inline minus button. Advisory composition warnings via `OutfitLayerOrder.warnings()` (multiple footwear, full-body + top/bottom conflicts). Tags edited via `TagPickerSheet` binding, changes applied only on save
- Manual item entry form with all attributes and optional photo
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
├── tags: [Tag]                   # @Relationship — many-to-many via Tag model
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

Tag (SwiftData @Model)
├── id: UUID
├── name: String                  # normalized: lowercased, trimmed, unique
├── isPredefined: Bool            # true for system tags (cannot be deleted)
├── colorHex: String?             # optional hex color for UI chip display
├── createdAt: Date
├── outfits: [Outfit]             # @Relationship — inverse of Outfit.tags
└── (v0.8: items: [ClothingItem]) # future relationship for item tagging
```

## Roadmap

### v0.7 — Outfit Tagging System
- **Tag model**: shared `Tag` SwiftData model with `name` (normalized: lowercased, trimmed, unique), `isPredefined`, `colorHex`, many-to-many relationship with `Outfit`
- **Predefined tags** (ship with app, cannot be deleted):
  - *Seasonal*: `spring`, `summer`, `fall`, `winter`
  - *Occasion*: `work`, `casual`, `date-night`, `formal`, `gym`, `travel`, `outdoor`
  - *Special*: `siri` (marks outfits for Siri quick-pick in v0.9)
- **Custom tags**: users can create, rename, and delete their own tags
- **AI auto-tagging**: outfit generation prompt includes the full list of available tag names; Claude returns a `tags: [String]` field in `OutfitSuggestionDTO`; matched against existing tags by normalized name, unrecognized names silently dropped
- **Agent auto-tagging**: outfits generated via the style agent also receive AI-assigned tags using the same mechanism
- Tags are additive — an outfit can have multiple tags (e.g. `["work", "winter", "siri"]`)

#### Tagging UI
- Tag chips on outfit cards (compact) and outfit detail view (full, editable)
- Tag filter bar in Outfits tab — replaces or augments the existing favorites filter; multi-select filtering
- Tag picker sheet on outfit detail (toggle existing tags, create new inline) — refactored to `@Binding var selectedTags: [Tag]` for reuse
- Tag management screen in Settings: view predefined tags, create/rename/delete custom tags, set chip colors
- Bulk-tag selection: long-press on outfit card enters selection mode (+ toolbar "Select" button); checkmark at bottom-right of cards
- Unified `BulkTagEditSheet`: shows all tags with checked/unchecked/mixed indicators for multi-outfit selection. Tap cycles mixed → unchecked → checked. Apply saves + exits selection mode
- Bulk delete selected outfits with confirmation dialog
- Improved tag chip contrast: `tagBackground` opacity 0.85, adjusted `tagText` for ~4.5:1 WCAG in both modes
- **Hit-testing rule**: `TagChipView` renders as plain label (not `Button`) when `onTap` is nil. In List rows, always use `.contentShape(Rectangle())` + `.onTapGesture` instead of wrapping `TagChipView` in a `Button` — disabled buttons still swallow taps

#### Outfit Editing
- Edit mode in `OutfitDetailView`: pencil toolbar button → inline `TextField` for name and occasion, item add/remove, tag editing
- Local `@State` copies of name, occasion, items, tags — Cancel reverts all, Done saves to SwiftData
- Item removal via minus button on each `OutfitItemCard`; item addition via `OutfitEditItemPicker` sheet (grid picker, excludes current items, multi-select)
- Advisory composition warnings via `OutfitLayerOrder.warnings()`: multiple footwear, multiple bottoms, multiple full-body, full-body + top/bottom conflict. Warnings only — never block the user
- `PickerGridCell` made `internal` (was `private`) for reuse across `ItemPickerSheet` and `OutfitEditItemPicker`

### v0.8 — Item Tagging & Agent Intent Detection

#### Reusable Patterns from v0.7
- `TagPickerSheet` already accepts `@Binding var selectedTags: [Tag]` — reuse directly for item tag editing, no refactoring needed
- `BulkTagEditSheet` mixed-state pattern (checked/unchecked/mixed) reusable for bulk item tagging in Wardrobe tab
- **Hit-testing rule**: never wrap `TagChipView` inside a `Button` in List rows — use `.contentShape(Rectangle())` + `.onTapGesture` instead
- `PickerGridCell` is `internal` — reusable across picker contexts
- `OutfitLayerOrder.warnings()` pattern can inform item-level validation if needed

#### Item Tagging
- Extend `Tag` model with `items: [ClothingItem]` relationship (many-to-many)
- Tag chips and filter bar in Wardrobe tab, tag picker on item detail
- Predefined item tags: `everyday`, `statement`, `layering`, `seasonal-rotate`, or reuse outfit tags where applicable
- AI auto-tagging on clothing scan: Claude returns suggested tags for scanned items

#### Agent Behavior (Intent Detection)
- When the user asks for something **new** ("give me a new outfit", "surprise me", "something different"), the agent defaults to **AI generation** via `generateOutfit` tool
- When the user asks for something **familiar** ("what do I usually wear", "something I've worn before", "my go-to work outfit", "a classic"), the agent defaults to **searching existing outfits** — prioritizes favorites, then tag-matched outfits, then all outfits
- Intent detection is handled in the agent system prompt; Claude interprets phrasing and picks the appropriate tool (`generateOutfit` vs `searchWardrobe`/outfit lookup)
- Tag-aware search: agent can filter by tags when searching ("find me a formal outfit" → search outfits tagged `formal`)
- If generation produces no viable result (all combinations exhausted or insufficient wardrobe), falls back to existing outfits with explanation

### v0.9 — Siri & HomePod Integration
- **App Intents** framework (iOS 16+) wrapping the same `AgentService` generation core
- Two intents:
  - **"What should I wear today?"** — weather + preferences + wardrobe → outfit → spoken response
  - **"What should I wear to [occasion]?"** — occasion-constrained generation → spoken response
- Single-turn mode only — no back-and-forth dialog flows for v1
- Uses `spokenSummary` from outfit generation as Siri's voice response
- Weather is mandatory; falls back to seasonal defaults if unavailable
- Accesses SwiftData store from App Intent extension process
- HomePod triggers via Siri intent forwarding to iPhone

#### Siri Outfit Selection
- Siri queries outfits tagged `"siri"`, filtered by current weather/season/occasion, preferring non-recently-worn
- **On-demand AI generation**: toggled off by default in Settings. When enabled, a warning explains potential 5–15s Siri response delay. If toggled on and no `siri`-tagged match found, falls back to live `AgentService` generation
- **Exhaustion fallback**: if all viable `siri`-tagged outfits have been recently worn or none match the context, re-suggests least-recently-worn from pool. If AI generation is enabled, tries generation first before falling back

#### Siri-Specific Considerations
- **Latency** — tagged-pool-first approach ensures near-instant Siri responses; AI generation is opt-in with explicit delay warning
- **Lean context** — single-turn loads everything at once (no progressive loading like chat), so compact wardrobe format is critical
- **Graceful degradation** — if weather unavailable, fall back to seasonal defaults based on date rather than failing. If no `siri`-tagged outfits exist and AI generation is off, prompt user to tag some outfits for Siri

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

