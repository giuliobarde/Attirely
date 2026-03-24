import Foundation

enum StyleContextHelper {

    static func comfortPreferencesString(from profile: UserProfile?) -> String? {
        guard let profile else { return nil }
        var lines: [String] = []

        if let cold = profile.coldSensitivityEnum {
            lines.append("Cold sensitivity: \(cold.rawValue)")
        }
        if let heat = profile.heatSensitivityEnum {
            lines.append("Heat sensitivity: \(heat.rawValue)")
        }
        if let notes = profile.bodyTempNotes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Body temp notes: \(notes.trimmingCharacters(in: .whitespaces))")
        }
        if let layering = profile.layeringPreferenceEnum {
            lines.append("Layering preference: \(layering.rawValue)")
        }
        if let comfort = profile.comfortVsAppearanceEnum {
            lines.append("Comfort vs appearance: \(comfort.rawValue)")
        }
        if let approach = profile.weatherDressingApproachEnum {
            lines.append("Weather dressing: \(approach.rawValue)")
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func styleContextString(from summary: StyleSummary?) -> String? {
        guard let summary else { return nil }
        guard summary.isAIEnriched else {
            return summary.overallIdentity
        }
        var ctx = "Overall: \(summary.overallIdentity)"
        for mode in summary.styleModesDecoded {
            ctx += "\n- \(mode.name) (\(mode.formality)): \(mode.description). Colors: \(mode.colorPalette.joined(separator: ", "))"
        }
        if let weather = summary.weatherBehavior {
            ctx += "\nWeather behavior: \(weather)"
        }
        return ctx
    }

    static func weatherContextString(from snapshot: WeatherSnapshot) -> String {
        let c = snapshot.current
        return """
        Weather: \(c.conditionDescription), \(String(format: "%.0f°C", c.temperature)) (feels like \(String(format: "%.0f°C", c.feelsLike)))
        Humidity: \(Int(c.humidity * 100))%
        Wind: \(String(format: "%.0f", c.windSpeed)) km/h
        Precipitation chance: \(Int(c.precipitationChance * 100))%
        """
    }
}
