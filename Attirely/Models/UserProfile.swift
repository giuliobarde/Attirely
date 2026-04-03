import Foundation
import SwiftData

enum TemperatureUnit: String, Codable, CaseIterable {
    case celsius = "°C"
    case fahrenheit = "°F"
}

enum ThemePreference: String, Codable, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

enum ColdSensitivity: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

enum HeatSensitivity: String, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

enum LayeringPreference: String, CaseIterable {
    case minimal = "Minimal layers"
    case happy = "Happy to layer"
    case loves = "Loves layering"
}

enum ComfortVsAppearance: String, CaseIterable {
    case comfort = "Comfort first"
    case balanced = "Balanced"
    case appearance = "Appearance first"
}

enum WeatherDressingApproach: String, CaseIterable {
    case light = "Dress light"
    case conditions = "Dress for conditions"
    case overdress = "Always overdress for warmth"
}

enum AgentMode: String, CaseIterable {
    case conversational = "Conversational"
    case direct = "Direct"
    case lastUsed = "Last used"
}

enum StyleModePreference: String, CaseIterable {
    case improve = "Improve"
    case expand  = "Expand"
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID

    // User details
    var name: String
    var profileImagePath: String?

    // Preferences (stored as raw strings for SwiftData compatibility)
    var temperatureUnitRaw: String
    var themePreferenceRaw: String

    // Location override
    var isLocationOverrideEnabled: Bool
    var locationOverrideName: String?
    var locationOverrideLat: Double?
    var locationOverrideLon: Double?

    // Style & Comfort questionnaire
    var coldSensitivity: String?
    var heatSensitivity: String?
    var bodyTempNotes: String?
    var layeringPreference: String?
    var selectedStyles: String?          // JSON-encoded [String]
    var comfortVsAppearance: String?
    var weatherDressingApproach: String?

    // Siri integration
    var isSiriAIGenerationEnabled: Bool = false

    // Agent mode
    var agentModeRaw: String?
    var agentLastActiveModeRaw: String?

    // Style mode
    var styleModeRaw: String = StyleModePreference.improve.rawValue
    var hasSeenStyleModeOnboarding: Bool = false

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Bridges

    var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
        set { temperatureUnitRaw = newValue.rawValue }
    }

    var themePreference: ThemePreference {
        get { ThemePreference(rawValue: themePreferenceRaw) ?? .system }
        set { themePreferenceRaw = newValue.rawValue }
    }

    var coldSensitivityEnum: ColdSensitivity? {
        get { coldSensitivity.flatMap { ColdSensitivity(rawValue: $0) } }
        set { coldSensitivity = newValue?.rawValue }
    }

    var heatSensitivityEnum: HeatSensitivity? {
        get { heatSensitivity.flatMap { HeatSensitivity(rawValue: $0) } }
        set { heatSensitivity = newValue?.rawValue }
    }

    var layeringPreferenceEnum: LayeringPreference? {
        get { layeringPreference.flatMap { LayeringPreference(rawValue: $0) } }
        set { layeringPreference = newValue?.rawValue }
    }

    var comfortVsAppearanceEnum: ComfortVsAppearance? {
        get { comfortVsAppearance.flatMap { ComfortVsAppearance(rawValue: $0) } }
        set { comfortVsAppearance = newValue?.rawValue }
    }

    var weatherDressingApproachEnum: WeatherDressingApproach? {
        get { weatherDressingApproach.flatMap { WeatherDressingApproach(rawValue: $0) } }
        set { weatherDressingApproach = newValue?.rawValue }
    }

    var agentMode: AgentMode {
        get { agentModeRaw.flatMap { AgentMode(rawValue: $0) } ?? .conversational }
        set { agentModeRaw = newValue.rawValue }
    }

    var agentLastActiveMode: AgentMode {
        get { agentLastActiveModeRaw.flatMap { AgentMode(rawValue: $0) } ?? .conversational }
        set { agentLastActiveModeRaw = newValue.rawValue }
    }

    var styleMode: StyleModePreference {
        get { StyleModePreference(rawValue: styleModeRaw) ?? .improve }
        set { styleModeRaw = newValue.rawValue }
    }

    var selectedStylesArray: [String] {
        get {
            guard let data = selectedStyles?.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return array
        }
        set {
            selectedStyles = String(data: (try? JSONEncoder().encode(newValue)) ?? Data(), encoding: .utf8) ?? "[]"
        }
    }

    init(name: String = "") {
        self.id = UUID()
        self.name = name
        self.temperatureUnitRaw = TemperatureUnit.celsius.rawValue
        self.themePreferenceRaw = ThemePreference.system.rawValue
        self.isLocationOverrideEnabled = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
