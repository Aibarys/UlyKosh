import Foundation

/// Представитель степной фауны или флоры, которого аул встречает на отрезке пути.
struct Fauna: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let note: String
}

/// Человек, который присоединяется к аулу на стоянке.
struct Character: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let role: String
    let emoji: String
    let story: String
}

/// Стоянка на маршруте. `km` — накопленное расстояние от кыстау.
struct Stop: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let km: Double
    let emoji: String
    let terrain: String
    let legend: String
    let fauna: [Fauna]
    let character: Character?
}

/// Испытание в пути: пройти `goalKm` за `days` дней после срабатывания на `triggerKm`.
struct RouteEvent: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let emoji: String
    let description: String
    let triggerKm: Double
    let goalKm: Double
    let days: Int
    let rewardText: String
    let reward: HerdDelta
}

struct Route: Identifiable {
    let id: String
    let title: String
    let season: String
    let intro: String
    let stops: [Stop]
    let events: [RouteEvent]

    var totalKm: Double { stops.last?.km ?? 0 }
}
