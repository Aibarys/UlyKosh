import Foundation

/// Свой маршрут из точки А в точку Б. Хранится в состоянии, тексты собираются при показе на текущем языке.
struct CustomRoute: Codable, Hashable {
    static let routeId = "custom"

    struct StopRef: Codable, Hashable {
        enum Kind: String, Codable { case place, landmark, steppe }
        var kind: Kind
        var placeId: Int?
        var landmarkKey: String?
        var km: Double
        var at: GeoPoint
        var terrain: Terrain
    }

    struct EventRef: Codable, Hashable {
        var template: String
        var index: Int
        var triggerKm: Double
    }

    var fromId: Int
    var toId: Int
    var path: RoadPath
    var stops: [StopRef]
    var events: [EventRef]

    var totalKm: Double { path.totalKm }
}

enum RouteBuilder {
    /// Знаковые места великих кочевий, которые могут встретиться на своём пути.
    private static let landmarkKeys: Set<String> = [
        "spring-syrdarya-ulytau/otyrar", "spring-syrdarya-ulytau/karatau", "spring-syrdarya-ulytau/betpak",
        "spring-syrdarya-ulytau/sarysu", "spring-syrdarya-ulytau/alasha",
        "autumn-ulytau-syrdarya/kengir", "autumn-ulytau-syrdarya/terekti", "autumn-ulytau-syrdarya/shu",
        "autumn-ulytau-syrdarya/turkistan",
        "summer-ulytau-jailau/aulietau", "summer-ulytau-jailau/karakengir", "summer-ulytau-jailau/joshy-khan",
        "winter-syrdarya-kystau/sauran"
    ]

    static var landmarks: [(key: String, stop: Stop)] {
        Routes.landmarkStops.filter { landmarkKeys.contains($0.key) }
    }

    // MARK: - Построение

    static func build(from: Place, to: Place, startDate: Date = .now,
                      places: PlaceStore = .shared, roads: RoadGraph = .shared) -> CustomRoute? {
        guard from.id != to.id, let path = roads.route(from: from.coordinate, to: to.coordinate), path.totalKm > 1 else { return nil }
        let total = path.totalKm

        // Кандидаты: населённые пункты и знаковые места возле дороги.
        let lats = path.points.map(\.lat), lons = path.points.map(\.lon)
        let bbox = (minLat: lats.min()! - 0.15, maxLat: lats.max()! + 0.15, minLon: lons.min()! - 0.2, maxLon: lons.max()! + 0.2)
        func inBox(_ p: GeoPoint) -> Bool { p.lat >= bbox.minLat && p.lat <= bbox.maxLat && p.lon >= bbox.minLon && p.lon <= bbox.maxLon }

        struct Candidate { var ref: CustomRoute.StopRef; var rank: Int }
        var candidates: [Candidate] = []
        for place in places.places where place.id != from.id && place.id != to.id && inBox(place.coordinate) {
            let limit = place.isTown ? 8.0 : 3.5
            let (d, km) = path.project(place.coordinate)
            guard d <= limit, km > 3, km < total - 3 else { continue }
            candidates.append(Candidate(ref: .init(kind: .place, placeId: place.id, km: km, at: place.coordinate,
                                                   terrain: TerrainClassifier.shared.terrain(at: place.coordinate, isCity: place.rank <= 2)),
                                        rank: place.rank))
        }
        var landmarkStops: [Candidate] = []
        for (key, stop) in landmarks where inBox(stop.coordinate) {
            let (d, km) = path.project(stop.coordinate)
            guard d <= 15, km > 3, km < total - 3 else { continue }
            landmarkStops.append(Candidate(ref: .init(kind: .landmark, landmarkKey: key, km: km, at: stop.coordinate, terrain: stop.terrain), rank: 0))
        }

        // Отбор: знаковые места и города всегда, сёла — чтобы между стоянками было 25–60 км.
        var chosen: [Candidate] = landmarkStops
        let towns = candidates.filter { $0.rank <= 3 }
        for town in towns where !chosen.contains(where: { abs($0.ref.km - town.ref.km) < 8 }) {
            chosen.append(town)
        }
        chosen.sort { $0.ref.km < $1.ref.km }
        let villages = candidates.filter { $0.rank > 3 }.sorted { $0.ref.km < $1.ref.km }
        var anchors = [0.0] + chosen.map(\.ref.km) + [total]
        var added: [Candidate] = []
        for i in 1..<anchors.count {
            var last = anchors[i - 1]
            let next = anchors[i]
            while next - last > 60 {
                let window = villages.filter { $0.ref.km >= last + 25 && $0.ref.km <= min(last + 60, next - 15) }
                if let pick = window.min(by: { abs($0.ref.km - (last + 40)) < abs($1.ref.km - (last + 40)) }) {
                    added.append(pick)
                    last = pick.ref.km
                } else {
                    // Нет ни одного села: стоянка в степи.
                    let km = min(last + 45, next - 15)
                    guard km > last + 10 else { break }
                    let at = point(on: path, atKm: km)
                    added.append(Candidate(ref: .init(kind: .steppe, km: km, at: at, terrain: TerrainClassifier.shared.terrain(at: at, isCity: false)), rank: 9))
                    last = km
                }
            }
        }
        anchors.removeAll()
        let middle = (chosen + added).sorted { $0.ref.km < $1.ref.km }.map(\.ref)

        let first = CustomRoute.StopRef(kind: .place, placeId: from.id, km: 0, at: from.coordinate,
                                        terrain: TerrainClassifier.shared.terrain(at: from.coordinate, isCity: from.rank <= 2))
        let last = CustomRoute.StopRef(kind: .place, placeId: to.id, km: total, at: to.coordinate,
                                       terrain: TerrainClassifier.shared.terrain(at: to.coordinate, isCity: to.rank <= 2))
        let stops = [first] + middle + [last]

        return CustomRoute(fromId: from.id, toId: to.id, path: path, stops: stops,
                           events: events(for: stops, total: total, startDate: startDate, seed: from.id &+ to.id))
    }

    static func point(on path: RoadPath, atKm km: Double) -> GeoPoint {
        guard let i = path.cumulativeKm.firstIndex(where: { $0 >= km }), i > 0 else { return path.points.first ?? GeoPoint(lat: 0, lon: 0) }
        let a = path.points[i - 1], b = path.points[i]
        let k0 = path.cumulativeKm[i - 1], k1 = path.cumulativeKm[i]
        let t = k1 > k0 ? (km - k0) / (k1 - k0) : 0
        return GeoPoint(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t)
    }

    // MARK: - Испытания

    private static func events(for stops: [CustomRoute.StopRef], total: Double, startDate: Date, seed: Int) -> [CustomRoute.EventRef] {
        guard total > 60 else { return [] }
        let season = Season.current(startDate)
        var result: [CustomRoute.EventRef] = []
        var km = min(45.0, total * 0.25)
        var index = 0
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed))
        while km < total - 25 {
            let terrain = stops.last(where: { $0.km <= km })?.terrain ?? .steppe
            let pool = EventTemplates.candidates(season: season, terrain: terrain)
            let template = pool[Int.random(in: 0..<pool.count, using: &rng)]
            result.append(.init(template: template.id, index: index, triggerKm: km))
            index += 1
            km += Double.random(in: 120...200, using: &rng)
        }
        return result
    }

    // MARK: - Превращение в маршрут для показа

    static func makeRoute(_ custom: CustomRoute, places: PlaceStore = .shared) -> Route {
        let from = places.place(custom.fromId)
        let to = places.place(custom.toId)
        let fromName = from?.name ?? "?"
        let toName = to?.name ?? "?"
        let landmarkMap = Dictionary(landmarks.map { ($0.key, $0.stop) }, uniquingKeysWith: { a, _ in a })

        var stops: [Stop] = []
        for (i, ref) in custom.stops.enumerated() {
            let id = "c\(i)"
            switch ref.kind {
            case .landmark:
                if let key = ref.landmarkKey, let base = landmarkMap[key] {
                    stops.append(Stop(id: id, name: base.name, subtitle: base.subtitle, km: ref.km, coordinate: ref.at,
                                      region: base.region, terrain: base.terrain, trailNotes: base.trailNotes,
                                      legend: base.legend, fauna: base.fauna, character: base.character, labelRank: 1))
                }
            case .place:
                guard let place = ref.placeId.flatMap(places.place) else { continue }
                stops.append(Stop(id: id, name: place.name, subtitle: subtitle(for: place), km: ref.km, coordinate: ref.at,
                                  region: place.regionName, terrain: ref.terrain, trailNotes: TrailNotes.notes(for: ref.terrain),
                                  legend: legend(for: place, terrain: ref.terrain), fauna: FaunaPools.pick(for: ref.terrain, seed: place.id),
                                  character: nil,
                                  labelRank: (i == 0 || i == custom.stops.count - 1 || place.rank <= 2) ? 1 : (place.rank == 3 ? 2 : 3)))
            case .steppe:
                stops.append(Stop(id: id, name: L("Стоянка в степи"), subtitle: L("Ночлег у дороги"), km: ref.km, coordinate: ref.at,
                                  region: places.nearest(to: ref.at, maxRank: 3)?.regionName ?? "",
                                  terrain: ref.terrain, trailNotes: TrailNotes.notes(for: ref.terrain),
                                  legend: L("Здесь нет ни села, ни колодца, только степь до горизонта. Путник ночует у дороги, кипятит чай на горелке и считает звёзды."),
                                  fauna: FaunaPools.pick(for: ref.terrain, seed: Int(ref.km)), character: nil, labelRank: 9))
            }
        }

        let events: [RouteEvent] = custom.events.compactMap { ref in
            EventTemplates.byId[ref.template]?.make(id: "\(ref.template)-\(ref.index)", triggerKm: ref.triggerKm)
        }
        let km = Fmt.km(custom.totalKm)
        return Route(
            id: CustomRoute.routeId,
            title: "\(fromName) → \(toName)",
            season: String(localized: "Свой путь · \(km) км"),
            intro: String(localized: "Путь из \(fromName) в \(toName): \(km) км по дорогам Казахстана, \(stops.count) стоянок. Каждый ваш шаг приближает путника к цели."),
            outro: String(localized: "Путник дошёл до \(toName). \(km) км позади, дневник полон историй."),
            stops: stops,
            events: events,
            path: custom.path
        )
    }

    private static func subtitle(for place: Place) -> String {
        if place.isCapital { return L("Столица") }
        if place.rank <= 2 { return L("Город") }
        if place.rank == 3 { return L("Районный центр") }
        return L("Село")
    }

    private static func legend(for place: Place, terrain: Terrain) -> String {
        let region = place.regionName
        let base: String
        if place.isCapital {
            base = String(localized: "\(place.name) — столица Казахстана. Широкие проспекты, новые кварталы и ветер из степи, который здесь дует круглый год.")
        } else if place.rank <= 2 {
            base = String(localized: "\(place.name) — город, \(region). Здесь можно отдохнуть, пополнить запасы и узнать дорогу дальше.")
        } else if place.rank == 3 {
            base = String(localized: "\(place.name) — районный центр, \(region). На базаре путнику продадут лепёшки в дорогу и расскажут, где лучше заночевать.")
        } else {
            base = String(localized: "\(place.name) — село, \(region). Путника здесь встречают чаем и расспросами о дороге.")
        }
        if place.pop >= 10_000 {
            let thousands = place.pop / 1000
            return base + " " + String(localized: "Здесь живёт около \(thousands) тыс. человек.")
        }
        return base
    }
}
