import SwiftUI

enum Theme {
    // MARK: - Adaptive Color Helper

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: - Dark Palette (raw UIColors)

    private static let darkBackground = UIColor(red: 0.098, green: 0.086, blue: 0.078, alpha: 1.0)  // #191615
    private static let darkSurface    = UIColor(red: 0.145, green: 0.129, blue: 0.118, alpha: 1.0)  // #25211E
    private static let darkElevated   = UIColor(red: 0.192, green: 0.173, blue: 0.157, alpha: 1.0)  // #312C28
    private static let darkStone      = UIColor(red: 0.580, green: 0.553, blue: 0.522, alpha: 1.0)  // #948D85
    private static let darkBorderUI   = UIColor(red: 0.235, green: 0.216, blue: 0.200, alpha: 1.0)  // #3C3733
    private static let darkBlush      = UIColor(red: 0.310, green: 0.243, blue: 0.212, alpha: 1.0)  // #4F3E36
    private static let darkTagTextUI  = UIColor(red: 0.855, green: 0.749, blue: 0.690, alpha: 1.0)  // #DABFB0

    // MARK: - Light Palette (raw UIColors)

    private static let lightObsidian = UIColor(red: 0.102, green: 0.094, blue: 0.090, alpha: 1.0)   // #1A1817
    private static let lightIvory    = UIColor(red: 0.976, green: 0.961, blue: 0.941, alpha: 1.0)   // #F9F5F0
    private static let lightStone    = UIColor(red: 0.741, green: 0.710, blue: 0.675, alpha: 1.0)   // #BDB5AC
    private static let lightBlush    = UIColor(red: 0.910, green: 0.816, blue: 0.765, alpha: 1.0)   // #E8D0C3
    private static let lightBorder   = UIColor(red: 0.910, green: 0.886, blue: 0.855, alpha: 1.0)   // #E8E2DA

    // MARK: - Color Tokens (adaptive)

    static let obsidian   = adaptive(light: lightObsidian, dark: lightIvory)
    static let ivory      = adaptive(light: lightIvory, dark: darkBackground)
    static let stone      = adaptive(light: lightStone, dark: darkStone)
    static let champagne  = Color(red: 0.788, green: 0.663, blue: 0.431)  // #C9A96E — fixed accent
    static let blush      = adaptive(light: lightBlush, dark: darkBlush)
    static let border     = adaptive(light: lightBorder, dark: darkBorderUI)

    // MARK: - Semantic Aliases (adaptive)

    static let primaryText      = obsidian
    static let secondaryText    = stone
    static let screenBackground = ivory

    static let cardFill = adaptive(
        light: UIColor.white.withAlphaComponent(0.6),
        dark: darkSurface.withAlphaComponent(0.6)
    )
    static let cardBorder = adaptive(
        light: lightBorder.withAlphaComponent(0.5),
        dark: darkBorderUI.withAlphaComponent(0.5)
    )
    static let glassCardTint = adaptive(
        light: lightIvory.withAlphaComponent(0.55),
        dark: darkSurface.withAlphaComponent(0.55)
    )
    static let scrim = adaptive(
        light: lightObsidian.withAlphaComponent(0.4),
        dark: UIColor.black.withAlphaComponent(0.5)
    )
    static let tagBackground = adaptive(
        light: lightBlush.withAlphaComponent(0.85),
        dark: darkBlush.withAlphaComponent(0.85)
    )
    static let tagText = adaptive(
        light: UIColor(red: 0.40, green: 0.28, blue: 0.22, alpha: 1.0),   // #664738
        dark: UIColor(red: 0.92, green: 0.84, blue: 0.78, alpha: 1.0)     // #EBD6C7
    )
    static let placeholderFill = adaptive(
        light: lightStone.withAlphaComponent(0.2),
        dark: darkStone.withAlphaComponent(0.2)
    )

    // MARK: - Category Pill States (adaptive)

    static let pillDefaultBg = adaptive(
        light: lightBorder.withAlphaComponent(0.6),
        dark: darkBorderUI.withAlphaComponent(0.8)
    )
    static let pillDefaultText = stone
    static let pillActiveBg    = adaptive(light: lightObsidian, dark: lightIvory)
    static let pillActiveText  = champagne
}

// MARK: - Card Modifier

struct ThemeCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.cardBorder, lineWidth: 0.5)
            )
            .shadow(color: Theme.obsidian.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Category Pill Modifier

struct ThemePillModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Theme.pillActiveBg : Theme.pillDefaultBg)
            .foregroundStyle(isActive ? Theme.pillActiveText : Theme.pillDefaultText)
            .clipShape(Capsule())
    }
}

// MARK: - Tag Modifier (Blush-based)

struct ThemeTagModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.tagBackground)
            .foregroundStyle(Theme.tagText)
            .clipShape(Capsule())
    }
}

// MARK: - Primary Button Style (CTA)

struct ThemePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.champagne)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
    }
}

// MARK: - Secondary Button Style

struct ThemeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Theme.obsidian)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

// MARK: - View Extensions

extension View {
    func themeCard() -> some View {
        modifier(ThemeCardModifier())
    }

    func themePill(isActive: Bool = false) -> some View {
        modifier(ThemePillModifier(isActive: isActive))
    }

    func themeTag() -> some View {
        modifier(ThemeTagModifier())
    }
}

// MARK: - ButtonStyle Extensions

extension ButtonStyle where Self == ThemePrimaryButtonStyle {
    static var themePrimary: ThemePrimaryButtonStyle { ThemePrimaryButtonStyle() }
}

extension ButtonStyle where Self == ThemeSecondaryButtonStyle {
    static var themeSecondary: ThemeSecondaryButtonStyle { ThemeSecondaryButtonStyle() }
}

// MARK: - Color Hex Extensions

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
