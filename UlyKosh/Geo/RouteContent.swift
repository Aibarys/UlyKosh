import Foundation

/// Определяет местность по геоданным карты: пустыни, хребты, реки, города.
final class TerrainClassifier: @unchecked Sendable {
    static let shared = TerrainClassifier()

    private var desert: [Cell: [GeoPoint]] = [:]
    private var ranges: [Cell: [GeoPoint]] = [:]
    private var rivers: [Cell: [GeoPoint]] = [:]

    private struct Cell: Hashable { let x: Int; let y: Int }
    private static func cell(_ p: GeoPoint) -> Cell { Cell(x: Int(floor(p.lon / 0.5)), y: Int(floor(p.lat / 0.5))) }

    init() {
        guard let data = MapData.load() else { return }
        for group in data.symbols {
            for c in group.points {
                let p = GeoPoint(lat: c[1], lon: c[0])
                switch group.kind {
                case "desert": desert[Self.cell(p), default: []].append(p)
                case "range": ranges[Self.cell(p), default: []].append(p)
                default: break
                }
            }
        }
        for river in data.rivers {
            for line in river.lines {
                for c in line {
                    let p = GeoPoint(lat: c[1], lon: c[0])
                    rivers[Self.cell(p), default: []].append(p)
                }
            }
        }
    }

    private func near(_ index: [Cell: [GeoPoint]], _ p: GeoPoint, within km: Double) -> Bool {
        let c = Self.cell(p)
        for dx in -1...1 {
            for dy in -1...1 {
                for q in index[Cell(x: c.x + dx, y: c.y + dy)] ?? [] where Geo.distanceKm(p, q) <= km {
                    return true
                }
            }
        }
        return false
    }

    func terrain(at p: GeoPoint, isCity: Bool) -> Terrain {
        if isCity { return .town }
        if near(ranges, p, within: 25) { return .mountains }
        if near(rivers, p, within: 6) { return .river }
        if near(desert, p, within: 30) { return .desert }
        return .steppe
    }
}

/// Короткие заметки о дороге для своих маршрутов, по местности.
enum TrailNotes {
    static func notes(for terrain: Terrain) -> [String] {
        switch terrain {
        case .steppe, .pasture:
            return [L("Ковыль по пояс, ветер гонит по степи серебряные волны"),
                    L("Машины проносятся мимо, а потом снова тишина до горизонта"),
                    L("Суслик перебежал дорогу и свистнул вслед"),
                    L("Впереди только столбы вдоль дороги и огромное небо")]
        case .desert:
            return [L("Песок скрипит под ногами, воду бережём"),
                    L("Вдоль дороги стоит саксаул, тени почти нет"),
                    L("Вдалеке видны силуэты верблюдов")]
        case .mountains:
            return [L("Дорога поднимается к перевалу, дышать тяжелее"),
                    L("Снежные вершины видны уже весь день"),
                    L("У обочины шумит горный ручей, можно умыться")]
        case .river, .ford:
            return [L("Вдоль реки тянутся тугаи, пахнет водой"),
                    L("Через мост гонят стадо, ждём на обочине"),
                    L("Рыбаки на берегу машут путнику")]
        case .town:
            return [L("Впереди огни города, к вечеру будем на месте"),
                    L("Обочина становится тротуаром, начинаются дома"),
                    L("У заправки можно купить воды и спросить дорогу")]
        case .ruins, .mausoleum:
            return [L("Впереди виден купол старого мавзолея"),
                    L("Курганы вдоль дороги напоминают, что здесь ходили тысячи лет")]
        }
    }
}

/// Звери и растения для своих маршрутов, собранные из великих кочевий.
enum FaunaPools {
    private static let byTerrain: [Terrain: [Fauna]] = {
        var result: [Terrain: [Fauna]] = [:]
        for route in Routes.all {
            for stop in route.stops {
                var list = result[stop.terrain] ?? []
                for f in stop.fauna where !list.contains(where: { $0.name == f.name }) { list.append(f) }
                result[stop.terrain] = list
            }
        }
        return result
    }()

    static func pick(for terrain: Terrain, seed: Int) -> [Fauna] {
        let sources: [Terrain]
        switch terrain {
        case .steppe: sources = [.pasture, .desert]
        case .town: sources = [.mausoleum, .river]
        case .river: sources = [.river, .ford]
        default: sources = [terrain]
        }
        let pool = sources.flatMap { byTerrain[$0] ?? [] }
        guard !pool.isEmpty else { return [] }
        let start = abs(seed) % pool.count
        return (0..<min(3, pool.count)).map { pool[(start + $0 * 7) % pool.count] }
    }
}

/// Испытания пешего пути.
struct EventTemplate {
    let id: String
    let seasons: Set<Season>?
    let terrains: Set<Terrain>?
    let icon: Pictogram
    let title: String
    let description: String
    let goalKm: Double
    let days: Int
    let rewardText: String
    let weather: SceneWeather

    func make(id: String, triggerKm: Double) -> RouteEvent {
        RouteEvent(id: id, title: title, icon: icon, description: description, triggerKm: triggerKm,
                   goalKm: goalKm, days: days, rewardText: rewardText, weather: weather)
    }
}

enum EventTemplates {
    static var all: [EventTemplate] {
        [
            EventTemplate(id: "buran", seasons: [.winter, .autumn], terrains: nil, icon: .snow,
                          title: L("Буран"),
                          description: L("Поднялся буран, дорогу заметает. До ближайшего жилья нужно дойти, пока видна обочина."),
                          goalKm: 12, days: 4, rewardText: L("Дошли до тёплого дома. Хозяева напоили чаем и оставили ночевать."), weather: .snow),
            EventTemplate(id: "frost", seasons: [.winter, .autumn], terrains: nil, icon: .snow,
                          title: L("Ночной мороз"),
                          description: L("Ночью ударил мороз, спать в степи нельзя. Нужно до темноты дойти до села."),
                          goalKm: 15, days: 4, rewardText: L("Успели до темноты. В селе нашёлся ночлег у печки."), weather: .snow),
            EventTemplate(id: "heat", seasons: [.summer], terrains: nil, icon: .sun,
                          title: L("Аптап"),
                          description: L("Жара за сорок, асфальт плавится. Идти можно только утром и вечером, а до тени ещё далеко."),
                          goalKm: 12, days: 4, rewardText: L("Добрались до тени и воды. Жару переждали у колодца."), weather: .clear),
            EventTemplate(id: "sandstorm", seasons: [.spring, .summer, .autumn], terrains: [.desert], icon: .whirlwind,
                          title: L("Песчаная буря"),
                          description: L("Навстречу идёт стена песка. Нужно добраться до укрытия, пока не замело дорогу."),
                          goalKm: 15, days: 4, rewardText: L("Переждали бурю в придорожном кафе. Шофёры рассказали о дороге дальше."), weather: .sand),
            EventTemplate(id: "thunderstorm", seasons: [.spring, .summer], terrains: nil, icon: .lightning,
                          title: L("Гроза"),
                          description: L("С запада идёт чёрная туча. До укрытия нужно дойти, пока не ударила молния."),
                          goalKm: 12, days: 3, rewardText: L("Укрылись вовремя. После грозы степь пахнет полынью."), weather: .rain),
            EventTemplate(id: "rain", seasons: [.spring, .autumn], terrains: nil, icon: .wave,
                          title: L("Затяжной дождь"),
                          description: L("Третий день льёт дождь, обочина раскисла. Нужно дойти до места, где можно просушиться."),
                          goalKm: 15, days: 5, rewardText: L("Просушились у костра. Дождь кончился, дорога снова твёрдая."), weather: .rain),
            EventTemplate(id: "flood", seasons: [.spring], terrains: [.river, .ford], icon: .wave,
                          title: L("Половодье"),
                          description: L("Река вышла из берегов и подтопила мост. Нужно успеть к броду выше по течению."),
                          goalKm: 10, days: 3, rewardText: L("Перешли вброд до большой воды."), weather: .clear),
            EventTemplate(id: "wolves", seasons: nil, terrains: [.steppe, .desert, .mountains, .pasture], icon: .wolf,
                          title: L("Волки у дороги"),
                          description: L("По ночам у дороги воют волки. Пастухи советуют не задерживаться в степи и идти до села."),
                          goalKm: 15, days: 4, rewardText: L("Дошли до села. Чабан рассказал, как отгонял стаю от отары."), weather: .clear),
            EventTemplate(id: "fire", seasons: [.summer, .autumn], terrains: [.steppe, .pasture], icon: .whirlwind,
                          title: L("Степной пожар"),
                          description: L("Сухую траву подожгла молния, дым стоит стеной. Нужно уйти от огня за реку или в село."),
                          goalKm: 15, days: 4, rewardText: L("Ушли от огня. Пожарные из района благодарят за предупреждение."), weather: .sand),
            EventTemplate(id: "headwind", seasons: nil, terrains: nil, icon: .whirlwind,
                          title: L("Встречный ветер"),
                          description: L("Весь день дует в лицо, каждый шаг даётся вдвое тяжелее. Нужно дотянуть до следующей стоянки."),
                          goalKm: 15, days: 4, rewardText: L("Ветер стих к вечеру. Ноги гудят, но путь пройден."), weather: .clouds)
        ]
    }

    static var byId: [String: EventTemplate] { Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) }) }

    static func candidates(season: Season, terrain: Terrain) -> [EventTemplate] {
        let list = all.filter { t in
            (t.seasons?.contains(season) ?? true) && (t.terrains?.contains(terrain) ?? true)
        }
        return list.isEmpty ? all.filter { $0.id == "headwind" } : list
    }
}
