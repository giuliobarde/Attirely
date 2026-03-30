---
description: Theme tokens, UI conventions, hit-testing rules, outfit display and editing patterns
globs:
  - "Attirely/Views/**"
  - "Attirely/Helpers/Theme.swift"
---

# Views & Theme Rules

## Theme System (`Theme.swift`)
- All views use `Theme.*` color tokens — **never hardcode colors**
- Adaptive light/dark via `Color(UIColor { traitCollection in ... })`; Champagne accent is fixed across modes
- ViewModifiers: `.themeCard()`, `.themePill()`, `.themeTag()`
- ButtonStyles: `.themePrimary`, `.themeSecondary`
- `ColorMapping.swift` maps color name strings to SwiftUI `Color` (for clothing item display, not UI theme)

## Hit-Testing
- Never wrap `TagChipView` inside a `Button` in List rows — use `.contentShape(Rectangle())` + `.onTapGesture` instead
- `PickerGridCell` is `internal` — reusable across picker contexts

## Agent Chat
- Agent tab shows starter screen by default; conversations open as `.fullScreenCover`
- Close button (X) warns about unsaved outfits via `.confirmationDialog` before dismissing
- `hasUnsavedOutfits`: checks `outfit.modelContext == nil` across conversation outfits
- `dismissChat()` cancels streaming, clears conversation, dismisses cover

## Outfit Display & Editing
- Layer-ordered cards via `OutfitLayerOrder`: Outerwear → Full Body → Top → Bottom → Footwear → Accessory
- Inline edit mode: local `@State` copies with Cancel/Done pattern
- Add items via `OutfitEditItemPicker`, remove via inline minus button
- Composition warnings from `OutfitLayerOrder.warnings()` are advisory only (multiple footwear, full-body + top/bottom conflicts)
- Tags edited via `TagPickerSheet` binding; changes applied only on save
- Footwear nudge: shown in `OutfitDetailView` when outfit has no footwear items (non-edit mode only)

## Scan Results & Outfit Detection
- `ResultsView` shows individual item cards with Save/Edit/Dismiss actions
- When single-image scan detects an outfit: inline editable outfit card appears above item list (name TextField, occasion TextField, reasoning text, save button)
- Outfit card visibility driven by `OutfitCompletenessValidator`: requires (Top+Bottom) OR Full Body; missing footwear is OK (`.validMissingFootwear` shows tip)
- "Save as Outfit" disabled until all items are saved or linked to existing
- Dismissing items re-evaluates completeness — card hides if outfit becomes invalid

## Duplicate "Use Existing" Flow
- `DuplicateReviewSheet` has three actions: "Save as New Item", "Use This One" (per `.sameItem` match), "Skip This Item"
- "Use This One" links to existing wardrobe item via `ScanViewModel.existingItemMapping`
- Linked items show `link.circle.fill` badge + "Undo" button in `ResultsView`
- Linked items participate in outfit save without creating duplicates
