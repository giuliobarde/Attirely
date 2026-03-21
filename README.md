# Attirely

Attirely is an iOS app that uses AI-powered vision to identify and analyze clothing items from photos, build a persistent digital wardrobe, and generate coordinated outfits. Take a picture or choose one from your library, and the app will detect each clothing item with detailed attributes — then help you put together outfits manually or with AI assistance. Powered by the Anthropic Claude API.

## Features

- **Scan clothing** — camera or photo library input, Claude vision API identifies items with 12+ attributes (type, color, fabric, pattern, formality, season, etc.)
- **Digital wardrobe** — persistent storage with grid/list views, category filtering, search, and full item editing
- **Manual item entry** — add items to your wardrobe manually via a form with optional photo attachment
- **Duplicate detection** — pre-filters by category+color, then uses Claude to classify same/similar/different items
- **Outfit generation** — create outfits manually by picking items, or let AI suggest up to 3 coordinated outfits based on occasion and season
- **Outfit display** — card-based layout with items ordered by layer (outerwear → tops → bottoms → footwear → accessories)
- **Favorites** — star outfits for quick access

## Setup

1. Open the project in Xcode 26+
2. In `Attirely/Resources/`, duplicate `Config.plist.example` and rename the copy to `Config.plist`
3. Open `Config.plist` and replace `your-api-key-here` with your [Anthropic API key](https://console.anthropic.com/)
4. Build and run on an iOS 26+ device or simulator

> **Note:** `Config.plist` is git-ignored to keep your API key out of version control.

## Camera

The camera feature requires a **physical iOS device**. On the simulator, only the photo library picker is available (the camera button will be hidden automatically).

If running on a device, the app will request camera permission on first use.

## Architecture

- **MVVM** — Models, ViewModels, Views, and Services are cleanly separated
- **No third-party dependencies** — uses only Apple frameworks and URLSession
- **SwiftUI** with `@Observable` for state management
- **SwiftData** for persistence

## Project Structure

```
Attirely/
├── App/AttirelyApp.swift              # App entry point + model container
├── Models/
│   ├── ClothingItem.swift             # Clothing item data model
│   ├── ClothingItemDTO.swift          # API response parsing
│   ├── ScanSession.swift              # Scan session grouping
│   ├── Outfit.swift                   # Outfit collection model
│   └── OutfitSuggestionDTO.swift      # AI outfit response parsing
├── Services/
│   ├── AnthropicService.swift         # Claude API (scan, duplicates, outfits)
│   ├── ConfigManager.swift            # API key configuration
│   └── ImageStorageService.swift      # Disk image storage
├── ViewModels/
│   ├── ScanViewModel.swift            # Scan flow state
│   ├── WardrobeViewModel.swift        # Wardrobe filtering/display
│   └── OutfitViewModel.swift          # Outfit creation/generation/favorites
├── Views/
│   ├── MainTabView.swift              # Tab bar (Scan + Outfits + Wardrobe)
│   ├── HomeView.swift                 # Scan tab
│   ├── ResultsView.swift              # Scan results display
│   ├── ClothingItemCard.swift         # Full item attribute card
│   ├── ImagePicker.swift              # Camera wrapper
│   ├── WardrobeView.swift             # Wardrobe grid/list
│   ├── ItemDetailView.swift           # Item detail/edit
│   ├── DuplicateWarningBanner.swift   # Duplicate alert UI
│   ├── DuplicateReviewSheet.swift     # Duplicate review modal
│   ├── OutfitsView.swift              # Outfit list tab
│   ├── OutfitDetailView.swift         # Layer-ordered outfit detail
│   ├── OutfitRowCard.swift            # Compact outfit list card
│   ├── OutfitGenerationContextSheet.swift  # AI generation options
│   ├── ItemPickerSheet.swift          # Manual outfit item picker
│   └── AddItemView.swift             # Manual wardrobe item entry
├── Helpers/
│   ├── ColorMapping.swift             # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   └── OutfitLayerOrder.swift         # Category layer sorting
└── Resources/
    ├── Config.plist.example           # API key template
    └── Assets.xcassets                # App assets
```
