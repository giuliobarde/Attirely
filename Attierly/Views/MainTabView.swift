import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Scan", systemImage: "camera") {
                HomeView()
            }
            Tab("Wardrobe", systemImage: "tshirt") {
                WardrobeView()
            }
        }
    }
}
