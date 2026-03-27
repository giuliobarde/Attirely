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
