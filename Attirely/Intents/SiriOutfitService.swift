import CoreLocation
import Foundation
import SwiftData

enum SiriOutfitError: LocalizedError {
    case noWardrobeItems
    case noSiriOutfitsAndAIDisabled
    case generationFailed(String)
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .noWardrobeItems:
            "You don't have any items in your wardrobe yet. Open Attirely and scan some clothing to get started."
        case .noSiriOutfitsAndAIDisabled:
            "I don't have any outfits tagged for Siri. Open Attirely and tag your favorite outfits with the 'siri' tag, or enable AI generation in Settings."
        case .generationFailed(let detail):
            "I couldn't put an outfit together right now. \(detail)"
        case .apiKeyMissing:
            "Attirely's AI service isn't configured. Open the app to set it up."
        }
    }
}

struct SiriOutfitResult {
    let outfit: Outfit
    let spokenSummary: String
    let isNewlyGenerated: Bool
}

enum SiriOutfitService {

    // MARK: - Main Entry Point

    static func selectOutfit(occasion: String?, context: ModelContext) async throws -> SiriOutfitResult {
        // 1. Load context
        let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first
        let styleSummary = try? context.fetch(FetchDescriptor<StyleSummary>()).first
        let wardrobeItems = (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? []
        let allOutfits = (try? context.fetch(FetchDescriptor<Outfit>())) ?? []
        let allTags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []

        guard !wardrobeItems.isEmpty else {
            throw SiriOutfitError.noWardrobeItems
        }

        // 2. Fetch weather (best-effort)
        let snapshot = await fetchWeather(profile: profile)
        let currentSeason: String
        if let temp = snapshot?.current.temperature {
            let calendarSeason = SeasonHelper.currentSeason()
            currentSeason = SeasonHelper.weatherAdaptedSeason(calendarSeason: calendarSeason, temperatureCelsius: temp)
        } else {
            currentSeason = SeasonHelper.currentSeason()
        }

        // 3. Query siri-tagged outfits
        let siriTag = allTags.first { $0.scope == .outfit && $0.name == "siri" }
        let siriOutfits = siriTag.map { tag in
            allOutfits.filter { $0.tags.contains(where: { $0.id == tag.id }) }
        } ?? []

        // 4. Filter by season, weather, and occasion
        let filtered = filterOutfits(
            siriOutfits,
            season: currentSeason,
            currentTemp: snapshot?.current.temperature,
            occasion: occasion
        )

        // 5. Pick randomly from filtered pool
        if let chosen = filtered.randomElement() {
            chosen.lastSuggestedBySiriAt = Date()
            try? context.save()
            let summary = buildSpokenSummary(for: chosen)
            return SiriOutfitResult(outfit: chosen, spokenSummary: summary, isNewlyGenerated: false)
        }

        // 6. If pool empty, try unfiltered siri outfits (relax filters)
        if let chosen = siriOutfits.randomElement() {
            chosen.lastSuggestedBySiriAt = Date()
            try? context.save()
            let summary = buildSpokenSummary(for: chosen)
            return SiriOutfitResult(outfit: chosen, spokenSummary: summary, isNewlyGenerated: false)
        }

        // 7. AI generation fallback
        guard profile?.isSiriAIGenerationEnabled == true else {
            throw SiriOutfitError.noSiriOutfitsAndAIDisabled
        }

        return try await generateAndSave(
            occasion: occasion,
            season: currentSeason,
            snapshot: snapshot,
            profile: profile,
            styleSummary: styleSummary,
            wardrobeItems: wardrobeItems,
            allOutfits: allOutfits,
            allTags: allTags,
            siriTag: siriTag,
            context: context
        )
    }

    // MARK: - Weather Fetching

    private static func fetchWeather(profile: UserProfile?) async -> WeatherSnapshot? {
        let location: CLLocation

        if let profile, profile.isLocationOverrideEnabled,
           let lat = profile.locationOverrideLat, let lon = profile.locationOverrideLon {
            location = CLLocation(latitude: lat, longitude: lon)
        } else {
            let service = LocationService()
            guard let loc = try? await service.requestCurrentLocation() else {
                return nil
            }
            location = loc
        }

        let result = await WeatherService.fetch(location: location)
        switch result {
        case .success(let snapshot): return snapshot
        case .failure: return nil
        }
    }

    // MARK: - Filtering

    private static func filterOutfits(
        _ outfits: [Outfit],
        season: String,
        currentTemp: Double?,
        occasion: String?
    ) -> [Outfit] {
        var result = outfits

        // Filter by season: check seasonAtCreation or seasonal tags
        result = result.filter { outfit in
            // If outfit has a season recorded, check it matches
            if let outfitSeason = outfit.seasonAtCreation {
                if outfitSeason.lowercased() == season.lowercased() { return true }
            }

            // Check seasonal tags
            let seasonalTags = ["spring", "summer", "fall", "winter"]
            let outfitSeasonTags = outfit.tags.filter { seasonalTags.contains($0.name) }
            if !outfitSeasonTags.isEmpty {
                return outfitSeasonTags.contains { $0.name == season.lowercased() }
            }

            // No seasonal signals — include by default
            return true
        }

        // Filter by temperature range if available (±10°C)
        if let currentTemp {
            result = result.filter { outfit in
                guard let outfitTemp = outfit.weatherTempAtCreation else { return true }
                return abs(outfitTemp - currentTemp) <= 10
            }
        }

        // Filter by occasion if specified
        if let occasion, !occasion.isEmpty {
            let normalizedOccasion = occasion.lowercased()
            let occasionFiltered = result.filter { outfit in
                // Check outfit occasion
                if let outfitOccasion = outfit.occasion?.lowercased(),
                   outfitOccasion.contains(normalizedOccasion) || normalizedOccasion.contains(outfitOccasion) {
                    return true
                }
                // Check occasion-related tags
                if outfit.tags.contains(where: {
                    $0.name.contains(normalizedOccasion) || normalizedOccasion.contains($0.name)
                }) {
                    return true
                }
                return false
            }
            // Only apply occasion filter if it doesn't eliminate everything
            if !occasionFiltered.isEmpty {
                result = occasionFiltered
            }
        }

        return result
    }

    // MARK: - Spoken Summary (Template)

    private static func buildSpokenSummary(for outfit: Outfit) -> String {
        let name = outfit.displayName
        let items = outfit.items

        guard !items.isEmpty else {
            return "How about \(name)?"
        }

        let descriptions = items.map { "\($0.primaryColor.lowercased()) \($0.type.lowercased())" }

        if descriptions.count == 1 {
            return "How about \(name)? It's your \(descriptions[0])."
        } else if descriptions.count == 2 {
            return "How about \(name)? It's your \(descriptions[0]) and \(descriptions[1])."
        } else {
            let allButLast = descriptions.dropLast().joined(separator: ", ")
            let last = descriptions.last!
            return "How about \(name)? It's your \(allButLast), and \(last)."
        }
    }

    // MARK: - AI Generation Fallback

    private static func generateAndSave(
        occasion: String?,
        season: String,
        snapshot: WeatherSnapshot?,
        profile: UserProfile?,
        styleSummary: StyleSummary?,
        wardrobeItems: [ClothingItem],
        allOutfits: [Outfit],
        allTags: [Tag],
        siriTag: Tag?,
        context: ModelContext
    ) async throws -> SiriOutfitResult {
        guard wardrobeItems.count >= 2 else {
            throw SiriOutfitError.noWardrobeItems
        }

        // Verify API key is available
        do {
            _ = try ConfigManager.apiKey()
        } catch {
            throw SiriOutfitError.apiKeyMissing
        }

        // Apply occasion-based filtering
        let tier = occasion.flatMap { OccasionTier(fromString: $0) }
        let filterResult = OccasionFilter.filterItems(wardrobeItems, for: tier)
        let filterContext = OccasionFilter.buildFilterContext(from: filterResult)

        guard filterResult.items.count >= 2 else {
            throw SiriOutfitError.noWardrobeItems
        }

        // Score and select candidate items
        let observations = styleSummary?.activeObservations ?? []
        let scorerConfig = RelevanceScorerConfig(
            occasion: tier,
            season: season,
            currentTemp: snapshot?.current.temperature,
            observations: observations,
            allOutfits: allOutfits
        )
        let scoredItems = RelevanceScorer.selectCandidates(from: filterResult.items, config: scorerConfig)
        let candidateItems = scoredItems.map(\.item)
        let relevanceHints = Dictionary(uniqueKeysWithValues: scoredItems.map { ($0.item.id, $0.score) })
        let observationPrompt = ObservationManager.promptString(from: observations, forOccasion: tier)

        let weatherContext = snapshot.map { StyleContextHelper.weatherContextString(from: $0) }
        let comfortPrefs = StyleContextHelper.comfortPreferencesString(from: profile)
        let styleText = StyleContextHelper.styleContextString(from: styleSummary)

        let existingItemSets = allOutfits.prefix(20).map { outfit in
            outfit.items.map { $0.id.uuidString }.sorted()
        }

        let outfitTags = allTags.filter { $0.scope == .outfit }
        let tagNames = outfitTags.map(\.name)

        let suggestions = try await AnthropicService.generateOutfits(
            from: candidateItems,
            occasion: occasion,
            season: season,
            weatherContext: weatherContext,
            comfortPreferences: comfortPrefs,
            styleSummary: styleText,
            filterContext: filterContext,
            existingOutfitItemSets: Array(existingItemSets),
            availableTagNames: tagNames,
            observationContext: observationPrompt,
            itemRelevanceHints: relevanceHints
        )

        guard let suggestion = suggestions.first else {
            throw SiriOutfitError.generationFailed("Try again in a moment.")
        }

        let matchedItems = candidateItems.filter {
            suggestion.itemIDs.contains($0.id.uuidString)
        }
        let minRequired = min(3, suggestion.itemIDs.count)
        guard matchedItems.count >= minRequired else {
            throw SiriOutfitError.generationFailed("Try again in a moment.")
        }

        var resolvedTags = TagManager.resolveTags(from: suggestion.tags, allTags: allTags, scope: .outfit)

        // Auto-tag with "siri" so it enters the pool
        if let siriTag, !resolvedTags.contains(where: { $0.id == siriTag.id }) {
            resolvedTags.append(siriTag)
        }

        let outfit = Outfit(
            name: suggestion.name,
            occasion: suggestion.occasion,
            reasoning: suggestion.reasoning,
            isAIGenerated: true,
            items: matchedItems,
            tags: resolvedTags
        )

        // Merge wardrobe gap notes
        let mergedGaps = OccasionFilter.mergeGaps(clientSide: filterResult.wardrobeGaps, aiSide: suggestion.wardrobeGaps)
        outfit.wardrobeGaps = Outfit.encodeGaps(mergedGaps)

        // Capture weather snapshot
        if let snapshot {
            outfit.weatherTempAtCreation = snapshot.current.temperature
            outfit.weatherFeelsLikeAtCreation = snapshot.current.feelsLike
            outfit.seasonAtCreation = season
        }
        outfit.monthAtCreation = Calendar.current.component(.month, from: Date())
        outfit.lastSuggestedBySiriAt = Date()

        context.insert(outfit)
        try? context.save()

        let spokenSummary = suggestion.spokenSummary ?? buildSpokenSummary(for: outfit)
        return SiriOutfitResult(outfit: outfit, spokenSummary: spokenSummary, isNewlyGenerated: true)
    }
}
