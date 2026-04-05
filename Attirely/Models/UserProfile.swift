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

enum StyleDirection: String, CaseIterable {
    case italian  = "italian"
    case british  = "british"
    case preppy   = "preppy"
    case parisian = "parisian"
    case oldMoney = "oldMoney"
    case japanese = "japanese"

    var displayName: String {
        switch self {
        case .italian:  "Classic Italian"
        case .british:  "Classic British"
        case .preppy:   "Preppy / Ivy"
        case .parisian: "Parisian / French"
        case .oldMoney: "Old Money / Quiet Luxury"
        case .japanese: "Japanese / Scandinavian"
        }
    }

    var tagline: String {
        switch self {
        case .italian:  "Effortless, slightly imperfect elegance."
        case .british:  "Structured, understated, and built to last."
        case .preppy:   "Collegiate and clean."
        case .parisian: "Minimalist and quietly confident."
        case .oldMoney: "Dressed as though the wardrobe was inherited, not bought."
        case .japanese: "Precise, considered, and serene."
        }
    }

    var promptDescription: String {
        switch self {
        case .italian:
            """
            STYLE DIRECTION — CLASSIC ITALIAN / NEAPOLITAN:
            Effortless, slightly imperfect elegance. Think sprezzatura: a casually unbuttoned collar, \
            a soft-shouldered Neapolitan suit worn with ease, tonal dressing with a single unexpected detail. \
            Suggest combinations that feel considered but never stiff — dressed up, but as if it took no effort.
            """
        case .british:
            """
            STYLE DIRECTION — CLASSIC BRITISH:
            Structured, understated, and built to last. Think Savile Row tailoring, heritage fabrics \
            (tweed, flannel, hopsack), and restrained color palettes anchored by navy, grey, and brown. \
            Suggest combinations that feel polished and traditional without being showy.
            """
        case .preppy:
            """
            STYLE DIRECTION — PREPPY / IVY:
            Collegiate and clean. Think Oxford cloth button-downs, chinos, loafers, and layering with \
            crewneck sweaters or sport coats. Color palettes lean toward pastels, madras, and bold solids. \
            Suggest combinations that feel relaxed but put-together.
            """
        case .parisian:
            """
            STYLE DIRECTION — PARISIAN / FRENCH:
            Minimalist and quietly confident. Think well-fitted basics in a tight color palette \
            (navy, white, ecru, black), a Breton stripe, a perfectly draped overcoat. Nothing excessive, \
            nothing missing. Suggest combinations that feel effortless through restraint — fewer pieces, better chosen.
            """
        case .oldMoney:
            """
            STYLE DIRECTION — OLD MONEY / QUIET LUXURY:
            Dressed as though the wardrobe was inherited, not bought. Think muted earth tones, fine natural \
            fabrics (cashmere, wool, linen), no visible logos, and nothing that looks new. Suggest combinations \
            that feel expensive through quality and fit rather than anything flashy or trend-driven.
            """
        case .japanese:
            """
            STYLE DIRECTION — JAPANESE / SCANDINAVIAN TAILORING:
            Precise, considered, and serene. Think clean silhouettes, impeccable fabric selection, subtle \
            texture play, and a preference for neutral or monochromatic palettes with a single tonal accent. \
            Suggest combinations where every detail feels intentional and nothing is excessive.
            """
        }
    }
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
    var styleDirectionRaw: String?
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

    var styleDirection: StyleDirection? {
        get { styleDirectionRaw.flatMap { StyleDirection(rawValue: $0) } }
        set { styleDirectionRaw = newValue?.rawValue }
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
