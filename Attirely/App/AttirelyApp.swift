import SwiftUI
import SwiftData

@main
struct AttirelyApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: [ClothingItem.self, ScanSession.self, Outfit.self])
    }
}
