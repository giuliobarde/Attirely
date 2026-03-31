import SwiftUI

struct ColorMapping {
    private static let exactColors: [String: Color] = [
        // Core colors
        "black": .black,
        "white": .white,
        "gray": .gray,
        "grey": .gray,
        "red": .red,
        "blue": .blue,
        "green": .green,
        "yellow": .yellow,
        "orange": .orange,
        "pink": .pink,
        "purple": .purple,
        "brown": .brown,
        "teal": .teal,

        // Blues
        "navy": Color(red: 0.0, green: 0.0, blue: 0.5),
        "navy blue": Color(red: 0.0, green: 0.0, blue: 0.5),
        "light blue": Color(red: 0.68, green: 0.85, blue: 0.90),
        "dark blue": Color(red: 0.0, green: 0.0, blue: 0.55),
        "medium blue": Color(red: 0.0, green: 0.0, blue: 0.80),
        "sky blue": Color(red: 0.53, green: 0.81, blue: 0.92),
        "baby blue": Color(red: 0.69, green: 0.88, blue: 0.90),
        "royal blue": Color(red: 0.25, green: 0.41, blue: 0.88),
        "cobalt": Color(red: 0.0, green: 0.28, blue: 0.67),
        "cobalt blue": Color(red: 0.0, green: 0.28, blue: 0.67),
        "denim": Color(red: 0.08, green: 0.38, blue: 0.74),
        "denim blue": Color(red: 0.08, green: 0.38, blue: 0.74),

        // Grays
        "charcoal": Color(red: 0.21, green: 0.27, blue: 0.31),
        "light gray": Color(red: 0.83, green: 0.83, blue: 0.83),
        "light grey": Color(red: 0.83, green: 0.83, blue: 0.83),
        "dark gray": Color(red: 0.41, green: 0.41, blue: 0.41),
        "dark grey": Color(red: 0.41, green: 0.41, blue: 0.41),
        "silver": Color(red: 0.75, green: 0.75, blue: 0.75),
        "slate": Color(red: 0.44, green: 0.50, blue: 0.56),

        // Greens
        "forest green": Color(red: 0.13, green: 0.55, blue: 0.13),
        "dark green": Color(red: 0.0, green: 0.39, blue: 0.0),
        "olive": Color(red: 0.5, green: 0.5, blue: 0.0),
        "sage": Color(red: 0.72, green: 0.72, blue: 0.59),
        "mint": Color(red: 0.60, green: 0.88, blue: 0.73),
        "emerald": Color(red: 0.31, green: 0.78, blue: 0.47),

        // Oranges / Warm
        "rust": Color(red: 0.72, green: 0.25, blue: 0.05),
        "rust orange": Color(red: 0.72, green: 0.25, blue: 0.05),
        "burnt orange": Color(red: 0.80, green: 0.33, blue: 0.0),
        "coral": Color(red: 1.0, green: 0.5, blue: 0.31),
        "peach": Color(red: 1.0, green: 0.80, blue: 0.64),
        "gold": Color(red: 1.0, green: 0.84, blue: 0.0),

        // Browns / Neutrals
        "tan": Color(red: 0.82, green: 0.71, blue: 0.55),
        "khaki": Color(red: 0.76, green: 0.69, blue: 0.57),
        "beige": Color(red: 0.96, green: 0.96, blue: 0.86),
        "cream": Color(red: 1.0, green: 0.99, blue: 0.82),
        "camel": Color(red: 0.76, green: 0.60, blue: 0.42),
        "camel brown": Color(red: 0.76, green: 0.60, blue: 0.42),
        "taupe": Color(red: 0.72, green: 0.62, blue: 0.53),
        "chocolate": Color(red: 0.48, green: 0.25, blue: 0.0),
        "coffee": Color(red: 0.44, green: 0.31, blue: 0.22),

        // Reds
        "burgundy": Color(red: 0.5, green: 0.0, blue: 0.13),
        "maroon": Color(red: 0.5, green: 0.0, blue: 0.0),
        "wine": Color(red: 0.45, green: 0.18, blue: 0.22),
        "crimson": Color(red: 0.86, green: 0.08, blue: 0.24),

        // Pinks
        "blush": Color(red: 0.87, green: 0.64, blue: 0.64),
        "rose": Color(red: 0.89, green: 0.41, blue: 0.53),
        "mauve": Color(red: 0.88, green: 0.69, blue: 0.80),

        // Whites / Off-whites
        "ivory": Color(red: 1.0, green: 1.0, blue: 0.94),
        "off-white": Color(red: 0.98, green: 0.96, blue: 0.90),
        "off white": Color(red: 0.98, green: 0.96, blue: 0.90),
        "ecru": Color(red: 0.76, green: 0.70, blue: 0.50),

        // Purples
        "lavender": Color(red: 0.71, green: 0.49, blue: 0.86),

        // Teals / Cyans
        "turquoise": Color(red: 0.25, green: 0.88, blue: 0.82),
        "aqua": Color(red: 0.0, green: 1.0, blue: 1.0),
        "cyan": Color(red: 0.0, green: 1.0, blue: 1.0),

        // Other
        "magenta": Color(red: 1.0, green: 0.0, blue: 1.0),
        "fuchsia": Color(red: 1.0, green: 0.0, blue: 1.0),
    ]

    // Distinctive color words for fuzzy fallback (not generic modifiers like "light"/"dark")
    private static let componentColors: [String: Color] = [
        "camel": Color(red: 0.76, green: 0.60, blue: 0.42),
        "rust": Color(red: 0.72, green: 0.25, blue: 0.05),
        "forest": Color(red: 0.13, green: 0.55, blue: 0.13),
        "sage": Color(red: 0.72, green: 0.72, blue: 0.59),
        "mint": Color(red: 0.60, green: 0.88, blue: 0.73),
        "emerald": Color(red: 0.31, green: 0.78, blue: 0.47),
        "cobalt": Color(red: 0.0, green: 0.28, blue: 0.67),
        "coral": Color(red: 1.0, green: 0.5, blue: 0.31),
        "burgundy": Color(red: 0.5, green: 0.0, blue: 0.13),
        "maroon": Color(red: 0.5, green: 0.0, blue: 0.0),
        "navy": Color(red: 0.0, green: 0.0, blue: 0.5),
        "olive": Color(red: 0.5, green: 0.5, blue: 0.0),
        "charcoal": Color(red: 0.21, green: 0.27, blue: 0.31),
        "slate": Color(red: 0.44, green: 0.50, blue: 0.56),
        "ivory": Color(red: 1.0, green: 1.0, blue: 0.94),
        "lavender": Color(red: 0.71, green: 0.49, blue: 0.86),
        "turquoise": Color(red: 0.25, green: 0.88, blue: 0.82),
        "khaki": Color(red: 0.76, green: 0.69, blue: 0.57),
        "taupe": Color(red: 0.72, green: 0.62, blue: 0.53),
        "denim": Color(red: 0.08, green: 0.38, blue: 0.74),
        "peach": Color(red: 1.0, green: 0.80, blue: 0.64),
        "wine": Color(red: 0.45, green: 0.18, blue: 0.22),
        "crimson": Color(red: 0.86, green: 0.08, blue: 0.24),
        "mauve": Color(red: 0.88, green: 0.69, blue: 0.80),
        "chocolate": Color(red: 0.48, green: 0.25, blue: 0.0),
    ]

    static func color(for name: String) -> Color {
        let normalized = name
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " colored", with: "")
            .replacingOccurrences(of: " colour", with: "")

        // Exact match
        if let color = exactColors[normalized] {
            return color
        }

        // Fuzzy: check if the input contains a distinctive color word
        for (keyword, color) in componentColors {
            if normalized.contains(keyword) {
                return color
            }
        }

        return .gray
    }
}
