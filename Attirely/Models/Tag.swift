import Foundation
import SwiftUI
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String
    var isPredefined: Bool
    var colorHex: String?
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Outfit.tags)
    var outfits: [Outfit] = []

    /// Saved color, semantic default by tag name, or (custom tags only) a stable derived hue.
    var resolvedAccentColor: Color? {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        if let hex = Tag.semanticAccentHex(for: name), let color = Color(hex: hex) {
            return color
        }
        if !isPredefined {
            return Color(hex: Tag.derivedAccentHex(from: name))
        }
        return nil
    }

    var tagColor: Color {
        resolvedAccentColor ?? Theme.tagBackground
    }

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Representative accent for built-in tags (season, occasion, Siri).
    static func semanticAccentHex(for normalizedName: String) -> String? {
        switch normalizedName {
        case "spring": return "5AAB6B"
        case "summer": return "E8A838"
        case "fall": return "C4703A"
        case "winter": return "5B8FC7"
        case "work": return "3D5A80"
        case "casual": return "6B9E9E"
        case "date-night": return "B84D6B"
        case "formal": return "4A4554"
        case "gym": return "E07A5F"
        case "travel": return "5C7CFA"
        case "outdoor": return "4A8C4A"
        case "siri": return "6C5CE7"
        default: return nil
        }
    }

    /// Stable pastel accent for user-created tags when no `colorHex` is set.
    static func derivedAccentHex(from normalizedName: String) -> String {
        var h: UInt64 = 5381
        for byte in normalizedName.utf8 {
            h = ((h << 5) &+ h) &+ UInt64(byte)
        }
        let hue = Double(h % 360)
        let (r, g, b) = hslToRGB(h: hue, s: 0.44, l: 0.5)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Int, Int, Int) {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (rp, gp, bp): (Double, Double, Double) = switch h {
        case 0 ..< 60: (c, x, 0)
        case 60 ..< 120: (x, c, 0)
        case 120 ..< 180: (0, c, x)
        case 180 ..< 240: (0, x, c)
        case 240 ..< 300: (x, 0, c)
        default: (c, 0, x)
        }
        func byte(_ v: Double) -> Int {
            min(255, max(0, Int(round(v * 255))))
        }
        return (byte(rp + m), byte(gp + m), byte(bp + m))
    }

    init(name: String, isPredefined: Bool = false, colorHex: String? = nil) {
        self.name = Tag.normalized(name)
        self.isPredefined = isPredefined
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}
