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
- Key models: `ClothingItem`, `Outfit`, `UserProfile`, `StyleSummary`, `Tag`, `ScanSession`.
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
- Pure utility functions and domain helpers with no direct I/O.
- Key helpers: `OccasionFilter` (tier-based filtering), `RelevanceScorer` (candidate scoring), `ObservationManager` (behavioral observation lifecycle), `OutfitLayerOrder` (layer sorting + warnings), `OutfitCompletenessValidator`, `TagManager`, `Theme`.

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
- **Dev:** Read once from `Config.plist` at launch via `ConfigManager`. If missing or empty, surface a clear error — do not crash. Never hardcode. Never log. Never include in error messages.
- **Production target:** API key moves to the Cloudflare Worker (see Backend section below). The app will send a device ID header instead; `ConfigManager` and `Config.plist` will be retired.

## Backend — Cloudflare Worker (AI Proxy)

Goal: prevent API key exposure and rate-limit AI requests per device. Auth/sync is out of scope for now.

### Architecture
- Worker sits between the app and `api.anthropic.com`
- Anthropic key stored as a Wrangler secret — never in source or the app bundle
- App sends a `X-Device-ID` header (UUID generated once, stored in Keychain)
- Worker rate-limits by device ID using Cloudflare KV (e.g. 50 requests/day, daily TTL)
- Worker returns 429 when limit exceeded

### Endpoints
- `POST /v1/messages` — forwards JSON and streaming requests verbatim to Anthropic
- `GET /health` — health check

### SSE Streaming
- Worker must pipe the Anthropic SSE response back using `ReadableStream` / `TransformStream`
- Do NOT buffer the full response — the app starts rendering tokens immediately
- Test SSE end-to-end before adding rate limiting

### iOS Changes (when proxy is ready)
- `AnthropicService.apiURL` → Worker URL
- Add `X-Device-ID` header (Keychain-stored UUID, generated at first launch)
- Remove `x-api-key` header from requests
- `ConfigManager` / `Config.plist` retired for key storage

### Implementation Steps
1. Scaffold Worker: `wrangler init attirely-proxy`
2. Add secret: `wrangler secret put ANTHROPIC_API_KEY`
3. Implement non-streaming proxy, deploy, test against app
4. Implement SSE streaming passthrough, test against app
5. Add KV-based rate limiting
6. Update iOS `AnthropicService` to point at Worker URL + send device ID

### Project Location
Worker source lives in `/backend/` at the repo root (separate from the Xcode project).

## Version History
- **v0.8** — Scoped tagging system (outfit + item pools), agent intent detection, bulk item tagging
- **v0.9** — Siri & HomePod integration via in-app App Intents, template spoken summaries
- **v0.9.1** — Occasion-based outfit filtering with OccasionTier, wardrobe gap notes
- **v0.9.2** — SSE streaming, conversational outfit editing, chat as fullScreenCover
- **v0.10** — Style intelligence: agent behavioral notes, item formality floor, relevance scoring, tier-based filtering
- **v0.10.1** — Conversational agent mode: three-state toggle (Conversational/Direct/Last Used), item-anchored generation via `must_include_items`, color/attribute-aware wardrobe exploration, in-chat mode toggle
- **v0.10.2** — Outfit detection at scan time, "Use Existing" duplicate linking, footwear nudge
- **v0.10.3** — "Build an Outfit Around This" anchor item feature: wardrobe and start-fresh modes, multi-outfit generation (1–4, Claude-determined), collapsible outfit cards. Entry point on `ItemDetailView`. New: `AnchorOutfitResultDTO`, `AnchorOutfitBuilderViewModel`, `AnchorOutfitBuilderView`, `AnthropicService.generateAnchoredOutfits()`
- **v0.10.4** — "What should I buy?" agent quick option: new `suggestPurchases` tool, `PurchaseSuggestionDTO`, `AnthropicService.suggestPurchases()`. Purchase cards in `AgentMessageBubble` with compatibility count, pairs-with list, and "Style an outfit around this" pipe-in button
- **v0.10.5** — Agent plumbing split + ID-addressed tool inputs. `AgentViewModel` shrinks from 1119 → ~360 lines as an observable facade; heavy logic moves into `AgentConversationLoop` (SSE loop + history), `AgentToolExecutor` (7 tools), `AgentPromptBuilder` (cached + fresh system prompt), `OutfitMatcher` (alias + fuzzy resolution). VM conforms to `AgentToolHost` + `AgentLoopHost`. `generateOutfit` gains `must_include_item_ids`; `editOutfit` gains `outfit_id`, `remove_item_ids`, `add_item_ids` (6-hex UUID prefix aliases). Free-form descriptions retained as fallback. Wardrobe alias index inlined in system prompt when wardrobe ≤ 40 items.
- **v0.10.6** — Agent history compaction + parallel tool execution. `AgentConversationLoop` elides `tool_result.content` in turns older than the last 3 user exchanges (replaced with a short placeholder; `tool_use_id` pairing preserved for Anthropic API structural validity). Read-only tools (`searchWardrobe`, `searchOutfits`, `suggestPurchases`) run concurrently via `withTaskGroup`; mutating tools (`generateOutfit`, `editOutfit`, `updateStyleInsight`, `askUserQuestion`) run sequentially. Results reassembled in the model's original call order so UI ordering stays stable. Outcomes: bounded context cost on long conversations, real concurrency gain when Claude mixes a network-bound tool (`suggestPurchases`) with a search in one turn.
- **v0.10.7** — Agent polish pass. `askUserQuestion` is now single-shot per turn — duplicate calls in the same turn get an error `tool_result` instead of silently overwriting the previous question. Tool results are now factual: rendering directives ("Display these…", "Do not say the edit failed…") moved into a TOOL RESULT RENDERING block in the cached system prompt. New `AgentTelemetry` (Helpers/) tracks tool-call distribution, unknown-alias rate, fuzzy-fallback rate, duplicate questions, malformed tool-use JSON, and pruned pending outfits — all printed to console with `[AgentTelemetry]` prefix. `pruneOrphanedPendingOutfits()` runs after each turn so abandoned generated outfits don't accumulate in `pendingOutfit{Items,Tags}` / `sourceOutfitIDForCopy`. `SSETypes.parseToolInputJSON` logs malformed tool-use JSON via telemetry instead of silently coercing to `{}`. Tool descriptions in `AgentService.toolDefinitions` trimmed to "what" — the duplicated "when" routing rules now live only in the cached system prompt's INTENT DETECTION section.

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

### v0.11b — Cloudflare Worker Proxy (pre-TestFlight security)
- Cloudflare Worker proxies all Anthropic API calls
- Anthropic key removed from app bundle entirely
- Per-device rate limiting via Cloudflare KV
- iOS `AnthropicService` updated to call Worker + send `X-Device-ID`
- Designed to accept auth layer later without a rewrite

### Future Ideas
- User auth + login (bolt onto Worker)
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

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **Attirely** (152 symbols, 148 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## When Debugging

1. `gitnexus_query({query: "<error or symptom>"})` — find execution flows related to the issue
2. `gitnexus_context({name: "<suspect function>"})` — see all callers, callees, and process participation
3. `READ gitnexus://repo/Attirely/process/{processName}` — trace the full execution flow step by step
4. For regressions: `gitnexus_detect_changes({scope: "compare", base_ref: "main"})` — see what your branch changed

## When Refactoring

- **Renaming**: MUST use `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` first. Review the preview — graph edits are safe, text_search edits need manual review. Then run with `dry_run: false`.
- **Extracting/Splitting**: MUST run `gitnexus_context({name: "target"})` to see all incoming/outgoing refs, then `gitnexus_impact({target: "target", direction: "upstream"})` to find all external callers before moving code.
- After any refactor: run `gitnexus_detect_changes({scope: "all"})` to verify only expected files changed.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Tools Quick Reference

| Tool | When to use | Command |
|------|-------------|---------|
| `query` | Find code by concept | `gitnexus_query({query: "auth validation"})` |
| `context` | 360-degree view of one symbol | `gitnexus_context({name: "validateUser"})` |
| `impact` | Blast radius before editing | `gitnexus_impact({target: "X", direction: "upstream"})` |
| `detect_changes` | Pre-commit scope check | `gitnexus_detect_changes({scope: "staged"})` |
| `rename` | Safe multi-file rename | `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` |
| `cypher` | Custom graph queries | `gitnexus_cypher({query: "MATCH ..."})` |

## Impact Risk Levels

| Depth | Meaning | Action |
|-------|---------|--------|
| d=1 | WILL BREAK — direct callers/importers | MUST update these |
| d=2 | LIKELY AFFECTED — indirect deps | Should test |
| d=3 | MAY NEED TESTING — transitive | Test if critical path |

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/Attirely/context` | Codebase overview, check index freshness |
| `gitnexus://repo/Attirely/clusters` | All functional areas |
| `gitnexus://repo/Attirely/processes` | All execution flows |
| `gitnexus://repo/Attirely/process/{name}` | Step-by-step execution trace |

## Self-Check Before Finishing

Before completing any code modification task, verify:
1. `gitnexus_impact` was run for all modified symbols
2. No HIGH/CRITICAL risk warnings were ignored
3. `gitnexus_detect_changes()` confirms changes match expected scope
4. All d=1 (WILL BREAK) dependents were updated

## Keeping the Index Fresh

After committing code changes, the GitNexus index becomes stale. Re-run analyze to update it:

```bash
npx gitnexus analyze
```

If the index previously included embeddings, preserve them by adding `--embeddings`:

```bash
npx gitnexus analyze --embeddings
```

To check whether embeddings exist, inspect `.gitnexus/meta.json` — the `stats.embeddings` field shows the count (0 means no embeddings). **Running analyze without `--embeddings` will delete any previously generated embeddings.**

> Claude Code users: A PostToolUse hook handles this automatically after `git commit` and `git merge`.

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
