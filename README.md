# Attirely

Attirely is an iOS app that uses AI-powered vision to identify and analyze clothing items from photos, build a persistent digital wardrobe, and generate coordinated outfits. Take a picture or choose one from your library, and the app will detect each clothing item with detailed attributes — then help you put together outfits manually or with AI assistance. Powered by the Anthropic Claude API.

## Features

- **Scan clothing** — camera or photo library input, Claude vision API identifies items with 12+ attributes (type, color, fabric, pattern, formality, season, etc.)
- **Outfit detection at scan** — single-image scans automatically detect if the photo shows a complete outfit and present an editable outfit card alongside the individual items
- **Digital wardrobe** — persistent storage with grid/list views, category filtering, search, and full item editing
- **Manual item entry** — add items to your wardrobe manually via a form with optional photo attachment
- **Duplicate detection** — pre-filters by category+color, then uses Claude to classify same/similar/different items; "Use Existing" links scan results to existing wardrobe items instead of creating duplicates
- **Tagging system** — scoped outfit and item tag pools; bulk tagging from the wardrobe view; tag filter bar; full tag management screen
- **Outfit generation** — create outfits manually by picking items, or let AI suggest an outfit based on occasion, season, and current weather, with deduplication against existing outfits and footwear nudge when footwear is missing
- **Occasion-based filtering** — 10 occasion tiers (Casual → White Tie, Gym, Outdoor) with tier-appropriate item filtering; progressive relaxation restores categories filtered to zero; wardrobe gap notes surface when items are missing for an occasion
- **Weather-aware outfits** — real-time weather via WeatherKit (Open-Meteo fallback), compact toolbar indicator, weather detail sheet with hourly forecast, AI adapts outfit suggestions to temperature, precipitation, and conditions
- **Outfit display** — card-based layout with items ordered by layer (outerwear → tops → bottoms → footwear → accessories)
- **Favorites** — star outfits for quick access
- **Style Agent (chat)** — conversational AI assistant with SSE streaming; generates outfits, searches your wardrobe and outfit history, edits outfits in-place, and updates your style profile — all in natural language. Opens as a full-screen chat with save-before-dismiss protection
- **Agent mode toggle** — three-mode switch (Conversational / Direct / Last Used) controlling whether the agent explores your preferences before generating or acts immediately
- **Agent behavioral notes** — agent tracks style observations (color preferences, formality patterns, item dislikes, etc.) across conversations; high-confidence observations influence future outfit generation
- **Relevance scoring** — scores wardrobe candidates by outfit frequency, favorites, formality alignment, observations, season, and usage before sending to AI, keeping prompts focused and token-efficient
- **Item formality floor** — optional per-item minimum occasion (e.g., tuxedo locked to "Black Tie"); AI-detected on scan, user-editable in item detail
- **Profile page** — user name, profile photo, wardrobe summary stats, style & comfort questionnaire, and style summary display
- **Style & Comfort questionnaire** — cold/heat sensitivity, body temp notes, layering preference, style identity (multi-select tag grid), comfort vs appearance, and weather dressing approach
- **Style summary** — auto-generated from questionnaire via template, editable by user, displayed on profile page
- **AI style analysis** — Claude analyzes your wardrobe and outfit patterns to detect style modes, seasonal trends, wardrobe gaps, and weather-relative dressing behavior. Triggered automatically as your wardrobe grows, or manually via "Analyze/Re-analyze" button
- **Enriched style profile** — AI-detected style modes displayed as cards with color palette swatches, plus seasonal patterns, opportunities, and weather style sections
- **User preferences** — temperature unit (°C/°F) applied across all weather displays, theme preference (System/Light/Dark) with full dark mode, custom location override with city geocoding
- **Comfort-aware outfits** — AI outfit generation respects user's comfort preferences (cold/heat sensitivity, layering, weather dressing approach) as hard constraints
- **Siri & HomePod** — App Intents for "What should I wear today?" and "What should I wear to [occasion]?"; tagged outfits respond instantly, AI generation available as opt-in fallback
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
│   ├── ScanResponseDTO.swift          # Single-image scan wrapper (items + outfit)
│   ├── ScanSession.swift              # Scan session grouping
│   ├── Outfit.swift                   # Outfit collection model (+ weather snapshot)
│   ├── OutfitSuggestionDTO.swift      # AI outfit response parsing
│   ├── StyleAnalysisDTO.swift         # AI style analysis response parsing
│   ├── WeatherData.swift              # Weather data structs (ephemeral)
│   ├── UserProfile.swift              # User profile, preferences, style questionnaire
│   ├── StyleSummary.swift             # Style summary model (template/AI)
│   ├── Tag.swift                      # Scoped tag model (outfit/item pools)
│   ├── ChatMessage.swift              # Ephemeral agent conversation message
│   ├── AgentToolDTO.swift             # Agent tool use blocks and typed inputs
│   ├── AgentObservation.swift         # Behavioral observation struct + category enums
│   └── SSETypes.swift                 # SSE event enum + content block accumulator
├── Services/
│   ├── AnthropicService.swift         # Claude API (scan, duplicates, outfits, style analysis)
│   ├── AgentService.swift             # Style agent SSE streaming + non-streaming paths
│   ├── SSEStreamParser.swift          # Server-sent events parser
│   ├── ConfigManager.swift            # API key configuration
│   ├── ImageStorageService.swift      # Disk image storage
│   ├── LocationService.swift          # CoreLocation wrapper
│   └── WeatherService.swift           # WeatherKit + Open-Meteo fallback
├── ViewModels/
│   ├── ScanViewModel.swift            # Scan flow state + duplicate linking
│   ├── WardrobeViewModel.swift        # Wardrobe filtering/display
│   ├── OutfitViewModel.swift          # Outfit creation/generation/favorites
│   ├── WeatherViewModel.swift         # Weather state management
│   ├── ProfileViewModel.swift         # Profile state + analytics
│   ├── StyleViewModel.swift           # AI style analysis state + debounce
│   └── AgentViewModel.swift           # Agent chat state + streaming loop
├── Views/
│   ├── MainTabView.swift              # Tab bar (Agent + Wardrobe + Outfits + Profile)
│   ├── HomeView.swift                 # Scan tab
│   ├── ResultsView.swift              # Scan results + outfit detection card
│   ├── ScanItemEditSheet.swift        # Edit item attributes before saving
│   ├── ScanProgressView.swift         # Multi-image scan progress indicator
│   ├── ImageThumbnailStrip.swift      # Horizontal image strip for multi-image scans
│   ├── ClothingItemCard.swift         # Full item attribute card
│   ├── ImagePicker.swift              # Camera wrapper
│   ├── DuplicateWarningBanner.swift   # Duplicate alert UI
│   ├── DuplicateReviewSheet.swift     # Duplicate review modal with "Use Existing"
│   ├── WardrobeView.swift             # Wardrobe grid/list
│   ├── WardrobeFilterSheet.swift      # Advanced wardrobe filter options
│   ├── ItemDetailView.swift           # Item detail/edit (incl. formality floor)
│   ├── AddItemView.swift              # Manual wardrobe item entry
│   ├── OutfitsView.swift              # Outfit list tab
│   ├── OutfitDetailView.swift         # Layer-ordered outfit detail + footwear nudge
│   ├── OutfitRowCard.swift            # Compact outfit list card
│   ├── OutfitGenerationContextSheet.swift  # AI generation options (occasion, constraints)
│   ├── OutfitEditItemPicker.swift     # Add items to an outfit in edit mode
│   ├── ItemPickerSheet.swift          # Manual outfit item picker
│   ├── AgentView.swift                # Style agent chat (fullScreenCover)
│   ├── AgentMessageBubble.swift       # Chat message bubble component
│   ├── TagChipView.swift              # Reusable tag chip
│   ├── TagFilterBar.swift             # Horizontal tag filter strip
│   ├── TagPickerSheet.swift           # Tag picker for outfits/items
│   ├── BulkTagEditSheet.swift         # Bulk tag editing for wardrobe items
│   ├── TagManagementView.swift        # Full tag management screen
│   ├── PillPickerField.swift          # Tappable pill for single-value picker fields
│   ├── ColorSwatchPicker.swift        # Color swatch grid picker
│   ├── CollapsibleSection.swift       # Reusable collapsible card section
│   ├── WeatherWidgetView.swift        # Compact toolbar weather indicator
│   ├── WeatherDetailSheet.swift       # Weather detail modal
│   ├── ProfileView.swift              # Profile tab (details, prefs, analytics)
│   └── WardrobeAnalyticsView.swift    # Swift Charts wardrobe analytics
├── ViewModels/
├── Intents/
│   ├── WhatToWearTodayIntent.swift    # Siri "What should I wear today?"
│   ├── WhatToWearToIntent.swift       # Siri "What should I wear to [occasion]?"
│   ├── AttirelyShortcuts.swift        # AppShortcutsProvider with natural phrases
│   └── SiriOutfitService.swift        # Outfit selection logic for Siri intents
├── Helpers/
│   ├── Theme.swift                    # Brand design system (colors, modifiers, styles)
│   ├── ColorMapping.swift             # Color name → SwiftUI Color
│   ├── ClothingItemDisplayable.swift  # Protocol for DTO + Model
│   ├── OutfitLayerOrder.swift         # Category layer sorting + composition warnings
│   ├── OutfitCompletenessValidator.swift  # Outfit validity check for scan detection
│   ├── OccasionFilter.swift           # Tier-based item filtering + gap detection
│   ├── RelevanceScorer.swift          # Candidate scoring + category-balanced selection
│   ├── ObservationManager.swift       # Agent observation recording + pruning
│   ├── TagManager.swift               # Tag resolution + uniqueness enforcement
│   ├── TagSeeder.swift                # Default tag seeding on first launch
│   ├── StyleContextHelper.swift       # Style context assembly for AI prompts
│   ├── SeasonHelper.swift             # Season detection from date/weather
│   ├── TemperatureFormatter.swift     # °C/°F formatting helper
│   └── StyleSummaryTemplate.swift     # Deterministic style summary generator
└── Resources/
    ├── Config.plist.example           # API key template
    └── Assets.xcassets                # App assets
```
