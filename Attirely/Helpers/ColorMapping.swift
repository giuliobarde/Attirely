import SwiftUI

struct ColorMapping {
    static func color(for name: String) -> Color {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "black":
            return .black
        case "white":
            return .white
        case "gray", "grey":
            return .gray
        case "navy", "navy blue":
            return Color(red: 0.0, green: 0.0, blue: 0.5)
        case "blue":
            return .blue
        case "red":
            return .red
        case "green":
            return .green
        case "yellow":
            return .yellow
        case "orange":
            return .orange
        case "pink":
            return .pink
        case "purple":
            return .purple
        case "brown":
            return .brown
        case "beige":
            return Color(red: 0.96, green: 0.96, blue: 0.86)
        case "cream":
            return Color(red: 1.0, green: 0.99, blue: 0.82)
        case "olive":
            return Color(red: 0.5, green: 0.5, blue: 0.0)
        case "teal":
            return .teal
        case "burgundy":
            return Color(red: 0.5, green: 0.0, blue: 0.13)
        case "maroon":
            return Color(red: 0.5, green: 0.0, blue: 0.0)
        case "tan":
            return Color(red: 0.82, green: 0.71, blue: 0.55)
        case "khaki":
            return Color(red: 0.76, green: 0.69, blue: 0.57)
        case "charcoal":
            return Color(red: 0.21, green: 0.27, blue: 0.31)
        case "coral":
            return Color(red: 1.0, green: 0.5, blue: 0.31)
        case "gold":
            return Color(red: 1.0, green: 0.84, blue: 0.0)
        case "silver":
            return Color(red: 0.75, green: 0.75, blue: 0.75)
        case "denim blue", "denim":
            return Color(red: 0.08, green: 0.38, blue: 0.74)
        default:
            return .gray
        }
    }
}
