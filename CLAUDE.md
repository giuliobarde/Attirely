# Attirely — Project Guide

## What is Attirely?
A wardrobe management iOS app. Users scan clothing via camera/photo library, the app identifies items using Claude's vision API, and builds a persistent digital wardrobe. Users can generate outfits manually or with AI assistance.

## Maintenance Rule
After implementing a version milestone, update this `CLAUDE.md` and any relevant `.claude/rules/` files to reflect the changes. This includes new files, updated descriptions, and roadmap progress. Do NOT skip this step.

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

## Xcode Project Conventions
- `PBXFileSystemSynchronizedRootGroup` is enabled — new source files added to `Attirely/` are auto-detected. Do NOT manually edit `.pbxproj` to add source files.
- `GENERATE_INFOPLIST_FILE = YES` — add Info.plist keys via `INFOPLIST_KEY_*` build settings, not a standalone Info.plist file.
- `Config.plist` is git-ignored (contains API key). Never commit it.

## Architecture Rules (MVVM)

### Models (`Models/`)
- SwiftData `@Model` classes for persistence; `Codable` DTOs for API parsing.
- No business logic, no API calls, no UI code.
- See `.claude/rules/models.md` for gotchas and DTO conventions.

### Services (`Services/`)
- Handle all external I/O: API calls, file system, config reading.
- Return Swift types, not raw JSON. Throw typed errors, not generic ones.
- Services should be stateless where possible. The view model owns state.
- See `.claude/rules/api-integration.md` for Anthropic API and weather details.

### ViewModels (`ViewModels/`)
- Owns the mutable state that views observe (`@Observable`).
- Calls into services, maps results to view-ready state.
- Contains presentation logic (e.g., "should the retry button be visible?") but NOT layout/styling.
- One view model can serve multiple related views (e.g., `ScanViewModel` serves both `HomeView` and `ResultsView`).

### Views (`Views/`)
- Purely declarative SwiftUI. No `URLSession`, no file I/O, no business logic.
- Read state from view models. Trigger actions by calling view model methods.
- Extract reusable components into their own files (e.g., `ClothingItemCard`).
- All views use `Theme.*` tokens — never hardcode colors.
- See `.claude/rules/views-and-theme.md` for theme system and UI conventions.

### Helpers (`Helpers/`)
- Pure utility functions with no side effects. No state, no I/O.

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

## API Key
- Read once from `Config.plist` at launch via `ConfigManager`.
- If missing or empty, surface a clear error to the user — do not crash.
- Never hardcode the key. Never log it. Never include it in error messages.

## Version History
- **v0.8** — Scoped tagging system (outfit + item pools), agent intent detection, bulk item tagging
- **v0.9** — Siri & HomePod integration via in-app App Intents, template spoken summaries
- **v0.9.1** — Occasion-based outfit filtering with OccasionTier, wardrobe gap notes
- **v0.9.2** — SSE streaming, conversational outfit editing, chat as fullScreenCover
- **v0.10** — Style intelligence: agent behavioral notes, item formality floor, relevance scoring, tier-based filtering

## Roadmap

### v0.11 — Image Extraction & Confidence
- Crop/extract individual items from group photos into per-item images
- Background removal via Apple Vision framework (`VNGenerateForegroundInstanceMaskRequest`)
- Attribute confidence system: Claude returns per-attribute confidence (`observed`/`inferred`/`assumed`), stored in `attributeConfidence: String?` on `ClothingItem`
- Surface confidence to user: subtle indicator on inferred/assumed attributes, badge for mostly low-confidence items
- Re-scan merge workflow: user adds better photo, system re-runs and merges (user edits preserved, AI fields updated)
- New field: `cutoutImagePath: String?` on `ClothingItem`

### v0.12 — Visual Outfit Compositor
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

## Rules Reference
Detailed domain-specific guidance lives in `.claude/rules/` and loads on-demand:
- **`api-integration.md`** — Anthropic API, agent tools, SSE streaming, outfit generation pipeline, weather API
- **`models.md`** — SwiftData model gotchas, DTO conventions, Tag scope mechanics
- **`views-and-theme.md`** — Theme tokens, UI conventions, hit-testing rules, outfit display/editing patterns
- **`siri-intents.md`** — App Intents for Siri/HomePod, outfit selection algorithm, spoken summaries
- **`occasion-filtering.md`** — OccasionTier system, progressive relaxation, wardrobe gap notes, style weight scaling
