# Attirely — Project Guide

## Documentation Rules
After completing any code changes, **always update both `CLAUDE.md` and `README.md`** to reflect the current state of the project. This includes:
- New or removed files → update **Project Structure** in both files
- New features or changed behavior → update **Current State** in CLAUDE.md and **Features** in README.md
- New or changed models → update **Data Model Design** in CLAUDE.md
- New API methods or prompt changes → update **API Integration Details** in CLAUDE.md
- Roadmap items that are now implemented → move from **Roadmap** to **Current State**

## What is Attirely?
A wardrobe management iOS app. Users scan clothing via camera/photo library, the app identifies items using Claude's vision API, and builds a persistent digital wardrobe. Users can generate outfits manually or with AI assistance.

## Tech Stack
- **Language:** Swift (strict concurrency enabled)
- **UI:** SwiftUI
- **Min Target:** iOS 26.2
- **Storage:** SwiftData
- **AI:** Anthropic Claude API (vision + outfit generation)
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
│   ├── Outfit.swift                # SwiftData @Model (outfit collection)
│   └── OutfitSuggestionDTO.swift   # Codable struct (AI outfit parsing)
├── Services/
│   ├── AnthropicService.swift      # Claude API calls (scan, duplicates, outfits)
│   ├── ConfigManager.swift         # Reads API key from Config.plist
│   └── ImageStorageService.swift   # Save/load images on disk
├── ViewModels/
│   ├── ScanViewModel.swift
│   ├── WardrobeViewModel.swift
│   └── OutfitViewModel.swift       # Outfit creation, generation, favorites
├── Views/
│   ├── MainTabView.swift           # TabView (Scan + Outfits + Wardrobe)
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
│   └── AddItemView.swift           # Manual wardrobe item entry form
├── Helpers/
│   ├── Theme.swift                 # Brand design system: color tokens, ViewModifiers, ButtonStyles
│   ├── ColorMapping.swift          # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   └── OutfitLayerOrder.swift      # Category → layer sort order
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
- `ClothingItem` is a SwiftData `@Model` class for persistence. `ClothingItemDTO` is a `Codable` struct for API parsing. `ScanSession` and `Outfit` are SwiftData `@Model`s. `OutfitSuggestionDTO` is a `Codable` struct for AI outfit response parsing.
- No business logic, no API calls, no UI code.
- DTOs own their `CodingKeys` for JSON mapping (snake_case API ↔ camelCase Swift).
- `ClothingItem` uses `itemDescription` (not `description`) to avoid NSObject conflict.
- `Outfit` has a `displayName` computed property that falls back from `name` → `occasion` → formatted date.

### Services (`Services/`)
- Handle all external I/O: API calls, file system, config reading.
- `AnthropicService` is the only type that talks to the network. All API logic stays here.
- Return Swift types, not raw JSON. Throw typed errors, not generic ones.
- Services should be stateless where possible. The view model owns state.

### ViewModels (`ViewModels/`)
- Owns the mutable state that views observe (`@Published` / `@Observable`).
- Calls into services, maps results to view-ready state.
- Contains presentation logic (e.g., "should the retry button be visible?") but NOT layout/styling.
- One view model can serve multiple related views (e.g., `ScanViewModel` serves both `HomeView` and `ResultsView`).

### Views (`Views/`)
- Purely declarative SwiftUI. No `URLSession`, no file I/O, no business logic.
- Read state from view models. Trigger actions by calling view model methods.
- Extract reusable components into their own files (e.g., `ClothingItemCard`).

### Helpers (`Helpers/`)
- Pure utility functions with no side effects. No state, no I/O.
- `Theme` — brand design system: color tokens (`Theme.obsidian`, `.ivory`, `.stone`, `.champagne`, `.blush`, `.border`), semantic aliases (`Theme.primaryText`, `.secondaryText`, `.screenBackground`, `.cardFill`, `.cardBorder`), ViewModifiers (`ThemeCardModifier`, `ThemePillModifier`, `ThemeTagModifier`), and ButtonStyles (`ThemePrimaryButtonStyle`, `ThemeSecondaryButtonStyle`). All views use these tokens instead of hardcoded colors.
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

### Outfit Generation API
- Text-only request (no image) — sends wardrobe item attributes with UUIDs
- Returns JSON array of `OutfitSuggestionDTO` with `name`, `occasion`, `item_ids`, `reasoning`
- Prompt enforces: 3-6 items per outfit, exactly one footwear, max 3-4 colors, max 2 patterns, consistent formality
- Uses 2048 max tokens (vs 4096 for vision analysis)

### Prompt Location
All prompts (clothing analysis, duplicate detection, outfit generation) live as string constants inside `AnthropicService`. If prompts grow more complex in later versions, extract to a `Prompts/` directory with one file per prompt.

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

## Current State (v0.3.0) ✅
- Camera and photo library input
- Claude vision API integration for clothing detection
- Results displayed as cards with all attributes
- SwiftData persistence for clothing items, scan sessions, and outfits
- Images stored on disk (Documents/clothing-images/ and Documents/scan-images/)
- Wardrobe view with grid/list toggle and category filtering
- Item detail/edit view with all fields editable, AI originals shown as reference
- Save individual items or save all from scan results
- Duplicate detection: pre-filter by category+color, Claude-based comparison, user confirmation
- Tab-based navigation (Scan + Outfits + Wardrobe)
- **Outfit generation**: manual creation via item picker, AI-powered generation with occasion/season context
- **Outfit display**: card-based layout with items ordered by layer (Outerwear → Full Body → Top → Bottom → Footwear → Accessory)
- **Outfit management**: favorites, deletion, AI reasoning display
- Layer ordering via `OutfitLayerOrder` helper — deterministic sort by category, designed to be reusable by v0.5 visual compositor
- **Manual item entry**: add wardrobe items manually via form with Pickers for all attributes, optional photo attachment
- Error handling (missing key, network, API, empty results, insufficient wardrobe)
- **Brand design system**: centralized `Theme.swift` with color tokens (Obsidian, Ivory, Stone, Champagne, Blush, Border), reusable ViewModifiers (`.themeCard()`, `.themePill()`, `.themeTag()`), and ButtonStyles (`.themePrimary`, `.themeSecondary`). CHAMPAGNE set as AccentColor globally. IVORY screen backgrounds, glass-tinted cards, and consistent typography applied across all views.

## Roadmap

### v0.3.1 — Weather-Aware Outfit Recommendations (next)
- Integrate Apple WeatherKit (or a free weather API) to fetch current conditions and forecast for the user's location
- Pass weather context (temperature, conditions, humidity, wind) to the outfit generation prompt alongside occasion/season
- Weather-adaptive prompt guidance: suggest lighter fabrics and fewer layers in heat, heavier weight and outerwear in cold, water-resistant items in rain
- Display current weather summary in the `OutfitGenerationContextSheet` so the user sees what context the AI is working with
- Auto-populate the season picker based on current date/hemisphere
- Optional: let the user override or ignore weather context if they prefer manual season selection
- Requires `CoreLocation` for user location (request "when in use" permission) and either WeatherKit entitlement or a third-party weather API key in `Config.plist`

### v0.4 — Image Extraction & Confidence
- Crop/extract individual items from group photos into per-item images stored separately from the source scan image
- Use Apple Vision framework (`VNGenerateForegroundInstanceMaskRequest`) for background removal to produce clean cutouts on transparent backgrounds
- Potentially use Vision framework for object detection bounding boxes before sending to Claude
- **Attribute confidence system:** modify the scan prompt to have Claude return a confidence level per attribute — `observed` (clearly visible in the image), `inferred` (reasonable guess based on visible cues), `assumed` (generic default, low certainty). Store as a JSON map in `attributeConfidence` field on `ClothingItem`.
- Surface confidence to the user: inferred/assumed attributes shown with a subtle indicator so the user knows what the AI is guessing vs. seeing
- Items with mostly low-confidence attributes get a badge in the wardrobe prompting the user to "add a better photo"
- **Re-scan merge workflow:** user adds a dedicated close-up or flat-lay photo of an item. System re-runs extraction on the new photo and merges: user edits are always preserved, AI-generated fields are updated with the new (presumably better) values, confidence levels are upgraded

### v0.5 — Visual Outfit Compositor
Replace the card-based outfit layout from v0.3 with a **layered visual composition** where items appear stacked as they would on a body. The goal is an almost-3D effect: a t-shirt visible through an open jacket, jeans below the shirt hem, shoes at the bottom. Items have realistic spatial relationships and overlapping, not just a flat list.

#### Two sub-problems
1. **Isolation** — every item needs to exist as a clean cutout with transparent background. Groundwork laid in v0.4 (Vision framework background removal). Items scanned from outfit photos will have partial visibility; items scanned individually will be more complete.
2. **Normalization** — items photographed from different angles, distances, and lighting must be transformed into a consistent visual system so they compose together. A shirt from a selfie, a jacket from a flat-lay, and jeans from a product page cannot simply be stacked — they need matching perspective, scale, and lighting.

#### Planned approach: generative flat-lay standardization
Use a generative AI model to transform whatever source photo the user provided into a **standardized flat-lay product image**: front-facing, studio-lit, transparent background, proportional scale. This becomes the "compositing asset" for each item.

The compositor then stacks flat-lay images in z-order using category-based anchor points:
- Tops anchor at the shoulder line
- Bottoms anchor at the waist line
- Outerwear wraps around the top layer
- Footwear sits at the bottom
- Accessories placed contextually (scarves at neck, hats above, bags to the side)

Scaling is relative to a standard body proportion so items look right together regardless of original photo zoom level.

#### Key considerations and open questions
- **Fidelity trade-off:** generated flat-lays are approximations, not exact replicas. Colors may shift slightly, logos or graphics may not reproduce accurately, fabric texture is estimated. This is acceptable for outfit visualization ("does this combination work?") but the user should understand these are AI-rendered representations, not photographs. Consider a subtle label or visual treatment that distinguishes generated composites from real photos.
- **Flat-lay photo option:** when a user adds a real flat-lay photo of an item (shot on a clean surface, full item visible), prefer that over the AI-generated version. This gives power users a path to higher fidelity without requiring it from everyone.
- **Image generation provider:** evaluate options at the time of implementation — cloud APIs (Stability AI, DALL-E, etc.), on-device diffusion models (Core ML converted), or Apple generative frameworks if available. Key criteria: transparent background support, consistency across items, latency, and cost per generation.
- **Template system:** define silhouette geometry per garment sub-type (crew neck vs. v-neck vs. henley, slim jeans vs. wide leg vs. shorts, blazer vs. puffer vs. trench) for consistent anchor points and layering. This is significant design work — scope it before committing.
- **Caching:** generated flat-lays should be stored on disk (`flatLayImagePath` on `ClothingItem`) and only regenerated if the source image changes or the user requests it.

### Future Ideas
- iCloud sync via SwiftData + CloudKit
- Outfit calendar (what you wore when)
- Style analytics (most worn items, color distribution, etc.)
- Share outfits
- Seasonal wardrobe rotation suggestions
- Virtual try-on: user photo + generated outfit overlay (significant technical leap, requires pose estimation)

## Data Model Design

```
ClothingItem (SwiftData @Model) — IMPLEMENTED
├── id: UUID
├── type, category, primaryColor, secondaryColor, pattern
├── fabricEstimate, weight, formality, season, fit, statementLevel
├── itemDescription: String       # renamed from description (NSObject conflict)
├── brand: String?                # user-editable
├── notes: String?                # user-editable
├── imagePath: String?            # path to cropped item image on disk
├── sourceImagePath: String?      # path to original scan image
├── aiOriginalValues: String?     # JSON blob of original AI-detected values
├── createdAt: Date
├── updatedAt: Date
├── scanSession: ScanSession?     # inverse relationship
└── outfits: [Outfit]             # inverse relationship

ClothingItemDTO (Codable struct) — IMPLEMENTED
├── Same fields as API response (uses "description" not "itemDescription")
├── CodingKeys for snake_case mapping
└── Used only for API response parsing, then converted to ClothingItem

ScanSession (SwiftData @Model) — IMPLEMENTED
├── id: UUID
├── imagePath: String
├── date: Date
└── items: [ClothingItem]

Outfit (SwiftData @Model) — IMPLEMENTED
├── id: UUID
├── name: String?
├── occasion: String?
├── reasoning: String?            # AI explanation of why the outfit works
├── isAIGenerated: Bool
├── isFavorite: Bool
├── createdAt: Date
├── items: [ClothingItem]         # @Relationship(deleteRule: .nullify)
└── displayName: String           # computed: name → occasion → formatted date

OutfitSuggestionDTO (Codable struct) — IMPLEMENTED
├── name: String
├── occasion: String
├── itemIDs: [String]             # CodingKey: "item_ids"
├── reasoning: String
└── Used only for AI response parsing, then converted to Outfit
```

### Planned Model Extensions

```
ClothingItem — v0.4 additions
├── cutoutImagePath: String?      # path to background-removed cutout (transparent PNG)
└── attributeConfidence: String?  # JSON map of field name → "observed"/"inferred"/"assumed"

ClothingItem — v0.5 additions
└── flatLayImagePath: String?     # path to AI-generated or user-provided flat-lay image
```

## Duplicate Detection Strategy
When new items are scanned, compare against existing wardrobe:
1. Pre-filter existing items by `category` + `primaryColor` to find candidates (cheap, local)
2. If candidates exist, send the new item image + candidate descriptions to Claude
3. Claude classifies each pair: "same item" (skip), "similar but different" (add with note), "no match" (add)
4. Present results to user for final confirmation — never auto-skip without user approval