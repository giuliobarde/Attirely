import SwiftUI
import SwiftData
import CoreLocation

struct MainTabView: View {
    @State private var weatherViewModel = WeatherViewModel()
    @State private var styleViewModel = StyleViewModel()
    @Query private var profiles: [UserProfile]

    private var activeProfile: UserProfile? { profiles.first }

    init() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .medium)
        ]
        navAppearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .medium)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    var body: some View {
        TabView {
            Tab("Athena", systemImage: "bubble.left.and.text.bubble.right") {
                AgentView(weatherViewModel: weatherViewModel, styleViewModel: styleViewModel)
            }
            Tab("Wardrobe", systemImage: "tshirt") {
                WardrobeView(weatherViewModel: weatherViewModel, styleViewModel: styleViewModel)
            }
            Tab("Outfits", systemImage: "sparkles") {
                OutfitsView(weatherViewModel: weatherViewModel, styleViewModel: styleViewModel)
            }
            Tab("Profile", systemImage: "person") {
                ProfileView(styleViewModel: styleViewModel)
            }
        }
        .onAppear {
            syncPreferences()
            weatherViewModel.fetchWeather()
        }
        .onChange(of: activeProfile?.temperatureUnitRaw) {
            syncTemperatureUnit()
        }
        .onChange(of: activeProfile?.isLocationOverrideEnabled) {
            syncLocationOverride()
        }
        .onChange(of: activeProfile?.locationOverrideLat) {
            syncLocationOverride()
        }
    }

    private func syncPreferences() {
        syncTemperatureUnit()
        syncLocationOverride()
    }

    private func syncTemperatureUnit() {
        guard let profile = activeProfile else { return }
        weatherViewModel.temperatureUnit = profile.temperatureUnit
    }

    private func syncLocationOverride() {
        guard let profile = activeProfile else { return }
        if profile.isLocationOverrideEnabled,
           let lat = profile.locationOverrideLat,
           let lon = profile.locationOverrideLon {
            weatherViewModel.overrideLocation = CLLocation(latitude: lat, longitude: lon)
            weatherViewModel.overrideLocationName = profile.locationOverrideName
        } else {
            weatherViewModel.overrideLocation = nil
            weatherViewModel.overrideLocationName = nil
        }
        weatherViewModel.retry()
    }
}
