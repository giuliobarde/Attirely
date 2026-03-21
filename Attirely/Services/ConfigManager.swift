import Foundation

enum ConfigError: LocalizedError {
    case missingConfigFile
    case missingAPIKey
    case invalidAPIKey

    var errorDescription: String? {
        switch self {
        case .missingConfigFile:
            return "Config.plist not found. Duplicate Config.plist.example to Config.plist and add your Anthropic API key."
        case .missingAPIKey:
            return "ANTHROPIC_API_KEY not found in Config.plist."
        case .invalidAPIKey:
            return "API key in Config.plist is still the placeholder value. Replace it with your real key."
        }
    }
}

struct ConfigManager {
    static func apiKey() throws -> String {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw ConfigError.missingConfigFile
        }

        guard let key = dict["ANTHROPIC_API_KEY"] as? String else {
            throw ConfigError.missingAPIKey
        }

        guard !key.isEmpty, key != "your-api-key-here" else {
            throw ConfigError.invalidAPIKey
        }

        return key
    }
}
