import SwiftUI
import CoreLocation

enum WeatherLoadState {
    case idle
    case requestingPermission
    case loading
    case loaded(WeatherSnapshot)
    case permissionDenied
    case failed(String)
}

@Observable
class WeatherViewModel {
    var loadState: WeatherLoadState = .idle
    var isShowingDetail = false
    var userOverridesWeather = false
    var temperatureUnit: TemperatureUnit = .celsius
    var overrideLocation: CLLocation?
    var overrideLocationName: String?

    private let locationService = LocationService()

    var snapshot: WeatherSnapshot? {
        if case .loaded(let s) = loadState { return s }
        return nil
    }

    var isLoaded: Bool { snapshot != nil }

    var weatherContextString: String? {
        guard !userOverridesWeather, let s = snapshot else { return nil }
        let c = s.current
        // Always send Celsius to AI for consistency. Use "degC" (no degree symbol) to avoid UTF-8/Latin-1 corruption when Claude echoes the value back.
        return """
        Weather: \(c.conditionDescription), \(String(format: "%.0f degC", c.temperature)) (feels like \(String(format: "%.0f degC", c.feelsLike)))
        Humidity: \(Int(c.humidity * 100))%
        Wind: \(String(format: "%.0f", c.windSpeed)) km/h
        Precipitation chance: \(Int(c.precipitationChance * 100))%
        """
    }

    var suggestedSeason: String {
        guard let s = snapshot else {
            return SeasonHelper.currentSeason()
        }
        let calendarSeason = SeasonHelper.currentSeason()
        return SeasonHelper.weatherAdaptedSeason(
            calendarSeason: calendarSeason,
            temperatureCelsius: s.current.temperature
        )
    }

    func fetchWeather() {
        guard case .idle = loadState else { return }
        loadState = .requestingPermission

        Task {
            do {
                let location: CLLocation
                let cityName: String?

                if let override = overrideLocation {
                    location = override
                    cityName = overrideLocationName
                } else {
                    location = try await locationService.requestCurrentLocation()
                    loadState = .loading
                    cityName = await LocationService.reverseGeocode(location: location)
                }

                loadState = .loading
                let result = await WeatherService.fetch(location: location)
                switch result {
                case .success(let snapshot):
                    let enriched = WeatherSnapshot(
                        current: snapshot.current,
                        hourlyForecast: snapshot.hourlyForecast,
                        fetchedAt: snapshot.fetchedAt,
                        locationName: cityName
                    )
                    loadState = .loaded(enriched)
                case .failure(let error):
                    loadState = .failed(error.localizedDescription)
                }
            } catch is LocationError {
                loadState = .permissionDenied
            } catch {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    func retry() {
        loadState = .idle
        fetchWeather()
    }
}
