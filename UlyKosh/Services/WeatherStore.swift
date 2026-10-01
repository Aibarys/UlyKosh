import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Погода по местоположению: CoreLocation даёт координату, WeatherKit — текущие условия.
/// Координата округляется до 0,1°, чтобы в сервис погоды не уходило точное местоположение.
@MainActor
@Observable
final class WeatherStore: NSObject {
    static let shared = WeatherStore()

    enum Status: Equatable { case idle, needsPermission, denied, loading, ready, failed }

    private(set) var status: Status = .idle
    private(set) var temperature: Measurement<UnitTemperature>?
    private(set) var condition: WeatherCondition?
    private(set) var symbolName: String?
    private(set) var placeName: String?
    private(set) var location: CLLocation?
    private(set) var attributionMarkURL: URL?
    private(set) var attributionLegalURL: URL?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var lastFailure: Date?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var pendingPermissionCallback: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    /// Обновляет погоду, если разрешение уже есть и данные старше 30 минут. Сам разрешение не запрашивает.
    func refreshIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .needsPermission
        case .denied, .restricted:
            status = .denied
        default:
            if inFlight { return }
            if let lastFetch, Date.now.timeIntervalSince(lastFetch) < 30 * 60, status == .ready { return }
            // После отказа не долбим сервис: повтор не раньше чем через 5 минут.
            if let lastFailure, Date.now.timeIntervalSince(lastFailure) < 5 * 60, status == .failed { return }
            if status != .ready { status = .loading }
            inFlight = true
            manager.requestLocation()
        }
    }

    /// Запрашивает доступ к геолокации (по нажатию пользователя).
    func requestPermission(then callback: (() -> Void)? = nil) {
        pendingPermissionCallback = callback
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            refreshIfNeeded()
            callback?()
            pendingPermissionCallback = nil
        }
    }

    private func fetch(for raw: CLLocation) async {
        // Одна точка геолокации может прийти дважды: второй вызов отбрасываем, пока идёт первый.
        guard !fetching else { return }
        fetching = true
        defer { inFlight = false; fetching = false }
        // Геолокация может прислать несколько точек подряд: свежие данные не перезапрашиваем.
        if status == .ready, let lastFetch, Date.now.timeIntervalSince(lastFetch) < 60 { return }
        let rounded = CLLocation(latitude: (raw.coordinate.latitude * 10).rounded() / 10,
                                 longitude: (raw.coordinate.longitude * 10).rounded() / 10)
        location = rounded
        let point = GeoPoint(lat: rounded.coordinate.latitude, lon: rounded.coordinate.longitude)
        if let nearest = PlaceStore.shared.nearest(to: point, maxRank: 4), Geo.distanceKm(nearest.coordinate, point) < 40 {
            placeName = nearest.name
        } else {
            placeName = try? await CLGeocoder().reverseGeocodeLocation(rounded).first?.locality
        }
        do {
            let current = try await WeatherService.shared.weather(for: rounded, including: .current)
            temperature = current.temperature
            condition = current.condition
            symbolName = current.symbolName
            lastFetch = .now
            status = .ready
            if attributionMarkURL == nil, let attribution = try? await WeatherService.shared.attribution {
                attributionMarkURL = attribution.combinedMarkDarkURL
                attributionLegalURL = attribution.legalPageURL
            }
        } catch {
            status = .failed
            lastFailure = .now
            #if DEBUG
            print("[Weather] failed: \(error)")
            #endif
        }
        #if DEBUG
        if status == .ready { print("[Weather] ok: \(temperatureText ?? "?") \(condition?.description ?? "") at \(placeName ?? "?")") }
        #endif
    }

    /// Как реальная погода выглядит на сцене.
    var sceneWeather: SceneWeather? {
        guard status == .ready, let condition else { return nil }
        switch condition {
        case .rain, .drizzle, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms,
             .strongStorms, .sunShowers, .tropicalStorm, .hurricane:
            return .rain
        case .snow, .heavySnow, .flurries, .blizzard, .blowingSnow, .sleet, .wintryMix, .freezingRain,
             .freezingDrizzle, .hail, .sunFlurries:
            return .snow
        case .blowingDust, .haze, .smoky:
            return .sand
        case .cloudy, .mostlyCloudy, .foggy, .breezy, .windy:
            return .clouds
        default:
            return .clear
        }
    }

    var temperatureText: String? {
        guard let temperature else { return nil }
        let c = Int(temperature.converted(to: .celsius).value.rounded())
        return c > 0 ? "+\(c)°" : "\(c)°"
    }
}

extension WeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshIfNeeded()
            if self.isAuthorized {
                self.pendingPermissionCallback?()
            }
            if manager.authorizationStatus != .notDetermined { self.pendingPermissionCallback = nil }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await self.fetch(for: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.inFlight = false
            if self.status != .ready { self.status = .failed; self.lastFailure = .now }
        }
    }
}
