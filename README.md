# Attirely

Attirely is an iOS app that uses AI-powered vision to identify and analyze clothing items from photos, build a persistent digital wardrobe, and generate coordinated outfits. Take a picture or choose one from your library, and the app will detect each clothing item with detailed attributes — then help you put together outfits manually or with AI assistance. Powered by the Anthropic Claude API.

## Features

- **Scan clothing** — camera or photo library input, Claude vision API identifies items with 12+ attributes (type, color, fabric, pattern, formality, season, etc.)
- **Digital wardrobe** — persistent storage with grid/list views, category filtering, search, and full item editing
- **Manual item entry** — add items to your wardrobe manually via a form with optional photo attachment
- **Duplicate detection** — pre-filters by category+color, then uses Claude to classify same/similar/different items
- **Outfit generation** — create outfits manually by picking items, or let AI suggest a focused single outfit based on occasion, season, and current weather, with deduplication against existing outfits
- **Weather-aware outfits** — real-time weather via WeatherKit (Open-Meteo fallback), compact toolbar indicator, weather detail sheet with hourly forecast, AI adapts outfit suggestions to temperature, precipitation, and conditions
- **Outfit display** — card-based layout with items ordered by layer (outerwear → tops → bottoms → footwear → accessories)
- **Favorites** — star outfits for quick access
- **Profile page** — user name, profile photo, wardrobe summary stats, style & comfort questionnaire, and style summary display
- **Style & Comfort questionnaire** — cold/heat sensitivity, body temp notes, layering preference, style identity (multi-select tag grid), comfort vs appearance, and weather dressing approach
- **Style summary** — auto-generated from questionnaire via template, editable by user, displayed on profile page
- **AI style analysis** — Claude analyzes your wardrobe and outfit patterns to detect style modes, seasonal trends, wardrobe gaps, and weather-relative dressing behavior. Triggered automatically as your wardrobe grows, or manually via "Analyze/Re-analyze" button
- **Enriched style profile** — AI-detected style modes displayed as cards with color palette swatches, plus seasonal patterns, opportunities, and weather style sections
- **User preferences** — temperature unit (°C/°F) applied across all weather displays, theme preference (System/Light/Dark) with full dark mode, custom location override with city geocoding
- **Comfort-aware outfits** — AI outfit generation respects user's comfort preferences (cold/heat sensitivity, layering, weather dressing approach) as hard constraints
- **Dark mode** — warm espresso/charcoal dark palette with adaptive colors throughout; champagne accent stays consistent across modes
- **Wardrobe analytics** — category composition (bar chart), formality breakdown (donut chart), and color distribution (swatch grid) powered by Swift Charts
- **Brand design system** — centralized theme with Obsidian/Ivory/Stone/Champagne/Blush palette, reusable card/pill/tag modifiers, and consistent typography across all views

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
│   ├── Outfit.swift                   # Outfit collection model (+ weather snapshot)
│   ├── OutfitSuggestionDTO.swift      # AI outfit response parsing
│   ├── StyleAnalysisDTO.swift         # AI style analysis response parsing
│   ├── WeatherData.swift              # Weather data structs (ephemeral)
│   ├── UserProfile.swift             # User profile, preferences, style questionnaire
│   └── StyleSummary.swift            # Style summary model (template/AI)
├── Services/
│   ├── AnthropicService.swift         # Claude API (scan, duplicates, outfits, style analysis)
│   ├── ConfigManager.swift            # API key configuration
│   ├── ImageStorageService.swift      # Disk image storage
│   ├── LocationService.swift          # CoreLocation wrapper
│   └── WeatherService.swift           # WeatherKit + Open-Meteo fallback
├── ViewModels/
│   ├── ScanViewModel.swift            # Scan flow state
│   ├── WardrobeViewModel.swift        # Wardrobe filtering/display
│   ├── OutfitViewModel.swift          # Outfit creation/generation/favorites
│   ├── WeatherViewModel.swift         # Weather state management
│   ├── ProfileViewModel.swift        # Profile state + analytics
│   └── StyleViewModel.swift          # AI style analysis state + debounce
├── Views/
│   ├── MainTabView.swift              # Tab bar (Scan + Outfits + Wardrobe + Profile)
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
│   ├── AddItemView.swift             # Manual wardrobe item entry
│   ├── WeatherWidgetView.swift        # Compact toolbar weather indicator
│   ├── WeatherDetailSheet.swift       # Weather detail modal
│   ├── ProfileView.swift             # Profile tab (details, prefs, analytics)
│   └── WardrobeAnalyticsView.swift   # Swift Charts wardrobe analytics
├── Helpers/
│   ├── Theme.swift                    # Brand design system (colors, modifiers, styles)
│   ├── ColorMapping.swift             # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   ├── OutfitLayerOrder.swift         # Category layer sorting
│   ├── SeasonHelper.swift             # Season detection from date/weather
│   ├── TemperatureFormatter.swift    # °C/°F formatting helper
│   └── StyleSummaryTemplate.swift   # Deterministic style summary generator
└── Resources/
    ├── Config.plist.example           # API key template
    └── Assets.xcassets                # App assets
```
