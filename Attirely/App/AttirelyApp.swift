import SwiftUI
import SwiftData

@main
struct AttirelyApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .background(Theme.screenBackground)
                .tint(Theme.champagne)
        }
        .modelContainer(for: [ClothingItem.self, ScanSession.self, Outfit.self])
    }
}
