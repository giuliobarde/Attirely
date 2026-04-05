import SwiftUI
import SwiftData
import CoreLocation
import MapKit

@Observable
class ProfileViewModel {
    var isEditingName = false
    var editedName = ""
    var isGeocodingLocation = false
    var locationError: String?
    var locationCityInput = ""

    // Style summary editing
    var isEditingStyleSummary = false
    var editedStyleSummary = ""

    private var modelContext: ModelContext?

    // MARK: - Profile Singleton

    func ensureProfileExists(in context: ModelContext) {
        self.modelContext = context
        let descriptor = FetchDescriptor<UserProfile>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.isEmpty {
            let profile = UserProfile()
            context.insert(profile)
            try? context.save()
        }
    }

    // MARK: - Profile Photo

    func updateProfilePhoto(_ image: UIImage, profile: UserProfile) {
        if let oldPath = profile.profileImagePath {
            ImageStorageService.deleteImage(relativePath: oldPath)
        }
        if let path = try? ImageStorageService.saveProfileImage(image, id: profile.id) {
            profile.profileImagePath = path
            profile.updatedAt = Date()
            try? modelContext?.save()
        }
    }

    // MARK: - Name

    func saveName(_ name: String, profile: UserProfile) {
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.updatedAt = Date()
        try? modelContext?.save()
        isEditingName = false
    }

    // MARK: - Preferences

    func updateTemperatureUnit(_ unit: TemperatureUnit, profile: UserProfile) {
        profile.temperatureUnit = unit
        profile.updatedAt = Date()
        try? modelContext?.save()
    }

    func updateThemePreference(_ theme: ThemePreference, profile: UserProfile) {
        profile.themePreference = theme
        profile.updatedAt = Date()
        try? modelContext?.save()
    }

    // MARK: - Location Override

    func toggleLocationOverride(_ enabled: Bool, profile: UserProfile) {
        profile.isLocationOverrideEnabled = enabled
        profile.updatedAt = Date()
        try? modelContext?.save()
    }

    func geocodeAndSaveLocation(profile: UserProfile) {
        let cityName = locationCityInput.trimmingCharacters(in: .whitespaces)
        guard !cityName.isEmpty else { return }
        isGeocodingLocation = true
        locationError = nil

        Task {
            do {
                guard let request = MKGeocodingRequest(addressString: cityName) else {
                    locationError = "Could not find that location."
                    isGeocodingLocation = false
                    return
                }
                let mapItems = try await request.mapItems
                if let location = mapItems.first?.location {
                    let coordinate = location.coordinate
                    profile.locationOverrideName = cityName
                    profile.locationOverrideLat = coordinate.latitude
                    profile.locationOverrideLon = coordinate.longitude
                    profile.updatedAt = Date()
                    try? modelContext?.save()
                } else {
                    locationError = "Could not find that location."
                }
            } catch {
                locationError = "Location lookup failed. Check the city name."
            }
            isGeocodingLocation = false
        }
    }

    func clearLocationOverride(profile: UserProfile) {
        profile.locationOverrideName = nil
        profile.locationOverrideLat = nil
        profile.locationOverrideLon = nil
        profile.isLocationOverrideEnabled = false
        profile.updatedAt = Date()
        locationCityInput = ""
        try? modelContext?.save()
    }

    // MARK: - Style & Comfort Questionnaire

    func updateColdSensitivity(_ value: ColdSensitivity, profile: UserProfile) {
        profile.coldSensitivityEnum = value
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func updateHeatSensitivity(_ value: HeatSensitivity, profile: UserProfile) {
        profile.heatSensitivityEnum = value
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func updateBodyTempNotes(_ notes: String, profile: UserProfile) {
        profile.bodyTempNotes = notes.isEmpty ? nil : notes
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func updateLayeringPreference(_ value: LayeringPreference, profile: UserProfile) {
        profile.layeringPreferenceEnum = value
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func toggleStyle(_ style: String, profile: UserProfile) {
        var styles = profile.selectedStylesArray
        if let index = styles.firstIndex(of: style) {
            styles.remove(at: index)
        } else {
            styles.append(style)
        }
        profile.selectedStylesArray = styles
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func updateComfortVsAppearance(_ value: ComfortVsAppearance, profile: UserProfile) {
        profile.comfortVsAppearanceEnum = value
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func updateWeatherDressingApproach(_ value: WeatherDressingApproach, profile: UserProfile) {
        profile.weatherDressingApproachEnum = value
        profile.updatedAt = Date()
        try? modelContext?.save()
        regenerateTemplateSummaryIfNeeded(profile: profile)
    }

    func updateAgentMode(_ mode: AgentMode, profile: UserProfile) {
        profile.agentMode = mode
        profile.updatedAt = Date()
        try? modelContext?.save()
    }

    func updateStyleMode(_ mode: StyleModePreference, profile: UserProfile) {
        profile.styleMode = mode
        profile.updatedAt = Date()
        try? modelContext?.save()
    }

    func updateStyleDirection(_ direction: StyleDirection, profile: UserProfile) {
        profile.styleDirection = direction
        profile.updatedAt = Date()
        try? modelContext?.save()
    }

    // MARK: - Style Summary

    func regenerateTemplateSummaryIfNeeded(profile: UserProfile) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<StyleSummary>()
        let existing = (try? context.fetch(descriptor))?.first

        // Don't overwrite AI-enriched summary
        if let existing, existing.isAIEnriched { return }

        let summaryText = StyleSummaryTemplate.generate(from: profile)

        let itemCount = ((try? context.fetchCount(FetchDescriptor<ClothingItem>())) ?? 0)
        let outfitCount = ((try? context.fetchCount(FetchDescriptor<Outfit>())) ?? 0)

        if let existing {
            existing.overallIdentity = summaryText
            existing.lastAnalyzedAt = Date()
            existing.itemCountAtLastAnalysis = itemCount
            existing.outfitCountAtLastAnalysis = outfitCount
            existing.analysisVersion += 1
        } else {
            let summary = StyleSummary(
                overallIdentity: summaryText,
                itemCountAtLastAnalysis: itemCount,
                outfitCountAtLastAnalysis: outfitCount
            )
            context.insert(summary)
        }
        try? context.save()
    }

    func updateSummaryText(_ text: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<StyleSummary>()
        guard let summary = (try? context.fetch(descriptor))?.first else { return }
        summary.overallIdentity = text
        summary.isUserEdited = true
        summary.lastAnalyzedAt = Date()
        try? context.save()
    }

    // MARK: - Analytics

    func categoryCounts(from items: [ClothingItem]) -> [(category: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { counts[item.category, default: 0] += 1 }
        return counts.map { (category: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    func formalityCounts(from items: [ClothingItem]) -> [(formality: String, count: Int)] {
        let order = ["Casual", "Smart Casual", "Business Casual", "Business", "Formal"]
        var counts: [String: Int] = [:]
        for item in items { counts[item.formality, default: 0] += 1 }
        return counts.map { (formality: $0.key, count: $0.value) }
            .sorted { order.firstIndex(of: $0.formality) ?? 99 < order.firstIndex(of: $1.formality) ?? 99 }
    }

    func colorCounts(from items: [ClothingItem]) -> [(color: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { counts[item.primaryColor, default: 0] += 1 }
        return counts.map { (color: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}
