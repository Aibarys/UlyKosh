import Foundation

/// Представитель степной фауны или флоры, которого аул встречает на отрезке пути.
struct Fauna: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: Pictogram
    let note: String
}

/// Человек, который присоединяется к аулу на стоянке.
struct Character: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let role: String
    let icon: Pictogram
    let story: String
}

/// Географическая точка в градусах.
struct GeoPoint: Codable, Hashable {
    let lat: Double
    let lon: Double
}

/// Стоянка на маршруте. `km` — накопленное расстояние от кыстау.
struct Stop: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let km: Double
    let coordinate: GeoPoint
    let region: String
    let terrain: Terrain
    /// Короткие фразы о том, как аул идёт к этой стоянке. Показываются на главном экране.
    let trailNotes: [String]
    let legend: String
    let fauna: [Fauna]
    let character: Character?
}

/// Испытание в пути: пройти `goalKm` за `days` дней после срабатывания на `triggerKm`.
struct RouteEvent: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let icon: Pictogram
    let description: String
    let triggerKm: Double
    let goalKm: Double
    let days: Int
    let rewardText: String
    let reward: HerdDelta
    /// Как испытание выглядит на сцене.
    let weather: SceneWeather
}

struct Route: Identifiable {
    let id: String
    let title: String
    let season: String
    let intro: String
    /// Фраза на главном экране, когда маршрут пройден.
    let outro: String
    let stops: [Stop]
    let events: [RouteEvent]

    var totalKm: Double { stops.last?.km ?? 0 }
}

enum Routes {
    static let all: [Route] = [SpringRoute.route, AutumnRoute.route]

    /// Весной и летом аул идёт на жайляу, осенью и зимой возвращается на кыстау.
    static func forStart(_ date: Date = .now) -> Route {
        switch Season.current(date) {
        case .spring, .summer: return SpringRoute.route
        case .autumn, .winter: return AutumnRoute.route
        }
    }

    static func byId(_ id: String) -> Route? { all.first { $0.id == id } }
}
