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
    /// С какого приближения подписывать стоянку на карте: 1 — сразу, 2 — ближе, 3 — совсем близко, 9 — никогда.
    var labelRank: Int = 1
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
    /// Запись в дневнике после успешного испытания.
    let rewardText: String
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
    /// Геометрия пути по дорогам для своих маршрутов; у великих кочевий путь рисуется по стоянкам.
    var path: RoadPath? = nil

    var totalKm: Double { stops.last?.km ?? 0 }
    var isCustom: Bool { id == CustomRoute.routeId }

    /// «Откуда → куда» по первой и последней стоянке.
    var endpoints: String { "\(stops.first?.name ?? "") → \(stops.last?.name ?? "")" }

    /// Где на местности находится путник, прошедший `km`.
    func coordinate(atKm km: Double) -> GeoPoint {
        let (points, kms): ([GeoPoint], [Double]) = path.map { ($0.points, $0.cumulativeKm) } ?? (stops.map(\.coordinate), stops.map(\.km))
        guard let first = points.first, let last = points.last else { return GeoPoint(lat: 48, lon: 67) }
        if km <= kms[0] { return first }
        for i in 1..<points.count where km <= kms[i] {
            let f = kms[i] > kms[i - 1] ? (km - kms[i - 1]) / (kms[i] - kms[i - 1]) : 0
            return GeoPoint(lat: points[i - 1].lat + (points[i].lat - points[i - 1].lat) * f,
                            lon: points[i - 1].lon + (points[i].lon - points[i - 1].lon) * f)
        }
        return last
    }
}

enum Routes {
    static let all: [Route] = [SpringRoute.route, SummerRoute.route, AutumnRoute.route, WinterRoute.route]

    /// Годовой круг: весной перекочёвка на жайлау, летом стоянка на жайлау,
    /// осенью перекочёвка на кыстау, зимой стоянка на кыстау.
    static func forStart(_ date: Date = .now) -> Route {
        switch Season.current(date) {
        case .spring: return SpringRoute.route
        case .summer: return SummerRoute.route
        case .autumn: return AutumnRoute.route
        case .winter: return WinterRoute.route
        }
    }

    static func byId(_ id: String) -> Route? { all.first { $0.id == id } }

    /// Все стоянки великих кочевий, доступные как знаковые места для своих маршрутов.
    static let landmarkStops: [(key: String, stop: Stop)] = all.flatMap { route in
        route.stops.map { (key: "\(route.id)/\($0.id)", stop: $0) }
    }
}
