import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Scan", systemImage: "camera") {
                HomeView()
            }
            Tab("Outfits", systemImage: "sparkles") {
                OutfitsView()
            }
            Tab("Wardrobe", systemImage: "tshirt") {
                WardrobeView()
            }
        }
    }
}
