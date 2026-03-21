import SwiftUI

enum Theme {
    // MARK: - Color Tokens

    static let obsidian   = Color(red: 0.102, green: 0.094, blue: 0.090)  // #1A1817
    static let ivory      = Color(red: 0.976, green: 0.961, blue: 0.941)  // #F9F5F0
    static let stone      = Color(red: 0.741, green: 0.710, blue: 0.675)  // #BDB5AC
    static let champagne  = Color(red: 0.788, green: 0.663, blue: 0.431)  // #C9A96E
    static let blush      = Color(red: 0.910, green: 0.816, blue: 0.765)  // #E8D0C3
    static let border     = Color(red: 0.910, green: 0.886, blue: 0.855)  // #E8E2DA

    // MARK: - Semantic Aliases

    static let primaryText      = obsidian
    static let secondaryText    = stone
    static let screenBackground = ivory
    static let cardFill         = Color.white.opacity(0.6)
    static let cardBorder       = border.opacity(0.5)
    static let glassCardTint    = ivory.opacity(0.55)
    static let scrim            = obsidian.opacity(0.4)
    static let tagBackground    = blush.opacity(0.7)
    static let tagText          = Color(red: 0.549, green: 0.416, blue: 0.353) // #8C6A5A
    static let placeholderFill  = stone.opacity(0.2)

    // MARK: - Category Pill States

    static let pillDefaultBg   = border.opacity(0.6)
    static let pillDefaultText = stone
    static let pillActiveBg    = obsidian
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
