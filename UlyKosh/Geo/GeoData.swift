import Foundation

enum Geo {
    /// Расстояние по поверхности Земли в километрах.
    static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let p = Double.pi / 180
        let d = 0.5 - cos((b.lat - a.lat) * p) / 2 + cos(a.lat * p) * cos(b.lat * p) * (1 - cos((b.lon - a.lon) * p)) / 2
        return 12_742 * asin(sqrt(max(0, d)))
    }

    /// Язык интерфейса: казахский или русский.
    static var prefersKazakh: Bool { Bundle.main.preferredLocalizations.first == "kk" }
}

/// Населённый пункт из GeoNames.
struct Place: Identifiable, Hashable, Codable {
    let id: Int
    let ru: String
    let kk: String
    let at: [Double]
    let pop: Int
    let rank: Int
    let region: String
    var cap: Bool?

    var coordinate: GeoPoint { GeoPoint(lat: at[1], lon: at[0]) }
    var name: String { Geo.prefersKazakh ? kk : ru }
    var isTown: Bool { rank <= 3 }
    var isCapital: Bool { cap == true }
    var regionName: String { PlaceStore.shared.regionName(region) }
}

/// Каталог населённых пунктов. Загружается один раз из kz-places.json.
final class PlaceStore: @unchecked Sendable {
    static let shared = PlaceStore()

    let places: [Place]
    private let regions: [String: [String]]
    private let byId: [Int: Place]

    private struct File: Decodable {
        let regions: [String: [String]]
        let places: [Place]
    }

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "kz-places", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            places = file.places
            regions = file.regions
        } else {
            places = []
            regions = [:]
        }
        byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func place(_ id: Int) -> Place? { byId[id] }

    func regionName(_ code: String) -> String {
        guard let names = regions[code] else { return "" }
        return Geo.prefersKazakh ? names[1] : names[0]
    }

    /// Поиск по русскому и казахскому названию. Пустой запрос возвращает крупные города.
    func search(_ query: String, limit: Int = 60) -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return places.filter { $0.rank <= 2 }.sorted { $0.pop > $1.pop } }
        func norm(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var prefix: [Place] = [], contains: [Place] = []
        for place in places {
            let ru = norm(place.ru), kk = norm(place.kk)
            if ru.hasPrefix(q) || kk.hasPrefix(q) { prefix.append(place) }
            else if ru.contains(q) || kk.contains(q) { contains.append(place) }
        }
        let order: (Place, Place) -> Bool = { ($0.rank, -$0.pop) < ($1.rank, -$1.pop) }
        return Array((prefix.sorted(by: order) + contains.sorted(by: order)).prefix(limit))
    }

    /// Ближайший населённый пункт не мельче заданного ранга.
    func nearest(to point: GeoPoint, maxRank: Int = 5) -> Place? {
        places.filter { $0.rank <= maxRank }.min { Geo.distanceKm($0.coordinate, point) < Geo.distanceKm($1.coordinate, point) }
    }
}

/// Путь по дорогам: точки и накопленные километры.
struct RoadPath: Codable, Hashable {
    var points: [GeoPoint]
    var cumulativeKm: [Double]
    var totalKm: Double { cumulativeKm.last ?? 0 }

    init(points: [GeoPoint]) {
        self.points = points
        var km: [Double] = []
        var acc = 0.0
        for (i, p) in points.enumerated() {
            if i > 0 { acc += Geo.distanceKm(points[i - 1], p) }
            km.append(acc)
        }
        cumulativeKm = km
    }

    /// Ближайшая точка пути к `p`: расстояние до пути и километр вдоль него.
    func project(_ p: GeoPoint) -> (distance: Double, km: Double) {
        var best = (distance: Double.infinity, km: 0.0)
        let cosLat = cos(p.lat * .pi / 180)
        for i in 1..<max(points.count, 1) {
            let a = points[i - 1], b = points[i]
            // Плоское приближение внутри отрезка, этого достаточно для расстояний в десятки км.
            let ax = (a.lon - p.lon) * cosLat, ay = a.lat - p.lat
            let bx = (b.lon - p.lon) * cosLat, by = b.lat - p.lat
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let qx = ax + t * dx, qy = ay + t * dy
            let d = sqrt(qx * qx + qy * qy) * 111.2
            if d < best.distance {
                best = (d, cumulativeKm[i - 1] + (cumulativeKm[i] - cumulativeKm[i - 1]) * t)
            }
        }
        return best
    }
}

/// Граф основных дорог Казахстана. Узлы — перекрёстки, рёбра хранят геометрию дороги.
final class RoadGraph: @unchecked Sendable {
    static let shared = RoadGraph()

    struct Edge { let a: Int; let b: Int; let km: Double; let geometry: [GeoPoint] }

    let nodes: [GeoPoint]
    let edges: [Edge]
    private let adjacency: [[(edge: Int, to: Int)]]

    init(bundle: Bundle = .main) {
        var nodes: [GeoPoint] = []
        var edges: [Edge] = []
        if let url = bundle.url(forResource: "kz-roads", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawNodes = json["nodes"] as? [[Double]],
           let rawEdges = json["edges"] as? [[Any]] {
            nodes = rawNodes.map { GeoPoint(lat: $0[1], lon: $0[0]) }
            for e in rawEdges {
                guard let a = e[0] as? Int, let b = e[1] as? Int, let km = (e[2] as? NSNumber)?.doubleValue,
                      let geom = e[3] as? [[Double]] else { continue }
                edges.append(Edge(a: a, b: b, km: km, geometry: geom.map { GeoPoint(lat: $0[1], lon: $0[0]) }))
            }
        }
        var adj = Array(repeating: [(edge: Int, to: Int)](), count: nodes.count)
        for (i, e) in edges.enumerated() {
            adj[e.a].append((i, e.b))
            adj[e.b].append((i, e.a))
        }
        self.nodes = nodes
        self.edges = edges
        adjacency = adj
    }

    private func nearestNode(_ p: GeoPoint) -> Int? {
        nodes.indices.min { Geo.distanceKm(nodes[$0], p) < Geo.distanceKm(nodes[$1], p) }
    }

    /// Кратчайший путь по дорогам. Начало и конец соединяются с ближайшими перекрёстками по прямой.
    func route(from start: GeoPoint, to end: GeoPoint) -> RoadPath? {
        guard let s = nearestNode(start), let t = nearestNode(end) else { return nil }
        var dist = Array(repeating: Double.infinity, count: nodes.count)
        var prev = Array(repeating: (node: -1, edge: -1), count: nodes.count)
        var heap = MinHeap()
        dist[s] = 0
        heap.push((0, s))
        while let (d, u) = heap.pop() {
            if u == t { break }
            if d > dist[u] { continue }
            for (edge, v) in adjacency[u] {
                let nd = d + edges[edge].km
                if nd < dist[v] {
                    dist[v] = nd
                    prev[v] = (u, edge)
                    heap.push((nd, v))
                }
            }
        }
        guard dist[t].isFinite else { return nil }

        var chain: [(from: Int, edge: Int)] = []
        var cur = t
        while cur != s {
            let step = prev[cur]
            chain.append((step.node, step.edge))
            cur = step.node
        }
        chain.reverse()

        var points: [GeoPoint] = [start, nodes[s]]
        for (from, edgeIndex) in chain {
            let e = edges[edgeIndex]
            let forward = e.a == from
            let inner = forward ? e.geometry : e.geometry.reversed()
            points.append(contentsOf: inner)
            points.append(nodes[forward ? e.b : e.a])
        }
        points.append(end)
        // Убираем повторы подряд.
        var cleaned: [GeoPoint] = []
        for p in points where cleaned.last.map({ Geo.distanceKm($0, p) > 0.05 }) ?? true {
            cleaned.append(p)
        }
        return RoadPath(points: cleaned)
    }
}

/// Двоичная куча для Дейкстры.
private struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ item: (Double, Int)) {
        items.append(item)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].0 <= items[i].0 { break }
            items.swapAt(parent, i)
            i = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(m, i)
                i = m
            }
        }
        return top
    }
}
