import SwiftUI
import SwiftData

@main
struct AttirelyApp: App {
    var body: some Scene {
        WindowGroup {
            ThemeWrapper()
                .tint(Theme.champagne)
        }
        .modelContainer(for: [ClothingItem.self, ScanSession.self, Outfit.self, UserProfile.self, StyleSummary.self, Tag.self])
    }
}

struct ThemeWrapper: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    private var colorScheme: ColorScheme? {
        guard let profile = profiles.first else { return nil }
        switch profile.themePreference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        MainTabView()
            .background(Theme.screenBackground)
            .preferredColorScheme(colorScheme)
            .onAppear {
                TagSeeder.seed(in: modelContext)
            }
    }
}
