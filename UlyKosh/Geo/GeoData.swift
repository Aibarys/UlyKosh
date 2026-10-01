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

    /// Пункт по id, а если каталог обновился и id сменился — ближайший к прежним координатам.
    func resolve(id: Int?, near point: GeoPoint, withinKm limit: Double = 5) -> Place? {
        if let id, let p = byId[id] { return p }
        guard let p = nearest(to: point, maxRank: 5), Geo.distanceKm(p.coordinate, point) <= limit else { return nil }
        return p
    }

    func regionName(_ code: String) -> String {
        guard let names = regions[code] else { return "" }
        return Geo.prefersKazakh ? names[1] : names[0]
    }

    /// Латинские ключи названий для поиска с английской раскладки: «Beskaragay», «Pavlodar».
    private lazy var latinKeys: [(ru: String, kk: String)] = places.map { (Self.latinKey($0.ru), Self.latinKey($0.kk)) }

    /// Грубая транслитерация в латиницу с выравниванием вариантов написания (zh/j, kh/h, y/i, q/k…).
    static func latinKey(_ s: String) -> String {
        let map: [String: String] = [
            "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "i",
            "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
            "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "iu", "я": "ia",
            "ә": "a", "ғ": "g", "қ": "k", "ң": "n", "ө": "o", "ұ": "u", "ү": "u", "һ": "h", "і": "i"
        ]
        var out = ""
        for ch in s.lowercased() {
            if let m = map[String(ch)] { out += m } else if ch.isLetter || ch.isNumber { out.append(ch) }
        }
        for (a, b) in [("shch", "s"), ("zh", "j"), ("kh", "h"), ("ts", "c"), ("ch", "c"), ("sh", "s"), ("ia", "a"), ("iu", "u"),
                       ("y", "i"), ("q", "k"), ("w", "v"), ("x", "ks"), ("ii", "i")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }

    /// Поиск по русскому и казахскому названию, а также латиницей. Пустой запрос возвращает крупные города.
    func search(_ query: String, limit: Int = 60) -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return places.filter { $0.rank <= 2 }.sorted { $0.pop > $1.pop } }
        func norm(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let latin = q.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
        let lq = latin ? Self.latinKey(q) : ""
        var prefix: [Place] = [], contains: [Place] = []
        for (i, place) in places.enumerated() {
            let ru = norm(place.ru), kk = norm(place.kk)
            if ru.hasPrefix(q) || kk.hasPrefix(q) { prefix.append(place) }
            else if ru.contains(q) || kk.contains(q) { contains.append(place) }
            else if latin, !lq.isEmpty {
                let keys = latinKeys[i]
                if keys.ru.hasPrefix(lq) || keys.kk.hasPrefix(lq) { prefix.append(place) }
                else if keys.ru.contains(lq) || keys.kk.contains(lq) { contains.append(place) }
            }
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

/// Граф дорог Казахстана из OpenStreetMap: от трасс до местных дорог между сёлами.
/// Узлы — развилки, рёбра хранят геометрию дороги. Формат kz-roads.bin описан в scripts/prepare_osm.py.
final class RoadGraph: @unchecked Sendable {
    static let shared = RoadGraph()

    struct Edge { let a: Int; let b: Int; let km: Double; let roadClass: Int; let geometry: [GeoPoint] }

    let nodes: [GeoPoint]
    let edges: [Edge]
    private let adjacency: [[(edge: Int, to: Int)]]
    private let grid: [Int: [Int]]
    private static let cell = 0.1

    private static func key(_ p: GeoPoint) -> Int { key(Int(floor(p.lon / cell)), Int(floor(p.lat / cell))) }
    private static func key(_ x: Int, _ y: Int) -> Int { (x + 10_000) * 100_000 + (y + 10_000) }

    init(bundle: Bundle = .main) {
        var nodes: [GeoPoint] = []
        var edges: [Edge] = []
        if let url = bundle.url(forResource: "kz-roads", withExtension: "bin"),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 14,
           data.prefix(4) == Data("KZRD".utf8) {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var o = 6
                func u16() -> Int { defer { o += 2 }; return Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) }
                func u32() -> Int { defer { o += 4 }; return Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
                func i32() -> Int32 { defer { o += 4 }; return Int32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: Int32.self)) }
                func i16() -> Int16 { defer { o += 2 }; return Int16(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: Int16.self)) }
                func f32() -> Float { defer { o += 4 }; return Float(bitPattern: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
                func u8() -> Int { defer { o += 1 }; return Int(raw.load(fromByteOffset: o, as: UInt8.self)) }
                let nodeCount = u32(), edgeCount = u32()
                var qx = [Int32](), qy = [Int32]()
                qx.reserveCapacity(nodeCount); qy.reserveCapacity(nodeCount); nodes.reserveCapacity(nodeCount)
                for _ in 0..<nodeCount {
                    let x = i32(), y = i32()
                    qx.append(x); qy.append(y)
                    nodes.append(GeoPoint(lat: Double(y) / 1e5, lon: Double(x) / 1e5))
                }
                edges.reserveCapacity(edgeCount)
                for _ in 0..<edgeCount {
                    let a = u32(), b = u32()
                    let km = Double(f32())
                    let cls = u8()
                    let n = u16()
                    var x = qx[a], y = qy[a]
                    var geom: [GeoPoint] = []
                    geom.reserveCapacity(n)
                    for _ in 0..<n {
                        x += Int32(i16()); y += Int32(i16())
                        geom.append(GeoPoint(lat: Double(y) / 1e5, lon: Double(x) / 1e5))
                    }
                    edges.append(Edge(a: a, b: b, km: km, roadClass: cls, geometry: geom))
                }
            }
        }
        var adj = Array(repeating: [(edge: Int, to: Int)](), count: nodes.count)
        for (i, e) in edges.enumerated() {
            adj[e.a].append((i, e.b))
            adj[e.b].append((i, e.a))
        }
        var grid: [Int: [Int]] = [:]
        for (i, p) in nodes.enumerated() { grid[Self.key(p), default: []].append(i) }
        self.nodes = nodes
        self.edges = edges
        adjacency = adj
        self.grid = grid
    }

    /// Ближайший перекрёсток: ищем по сетке кольцами, пока не найдём.
    func nearestNode(_ p: GeoPoint) -> Int? {
        guard !nodes.isEmpty else { return nil }
        let cx = Int(floor(p.lon / Self.cell)), cy = Int(floor(p.lat / Self.cell))
        var best: (Int, Double)?
        for ring in 0...60 {
            for dx in -ring...ring {
                for dy in -ring...ring where max(abs(dx), abs(dy)) == ring {
                    for i in grid[Self.key(cx + dx, cy + dy)] ?? [] {
                        let d = Geo.distanceKm(nodes[i], p)
                        if d < (best?.1 ?? .infinity) { best = (i, d) }
                    }
                }
            }
            // Узел внутри кольца ближе любого узла за его пределами.
            if let best, best.1 < Double(ring) * Self.cell * 70 { return best.0 }
        }
        return best?.0
    }

    /// Кратчайший путь по дорогам (A*). Начало и конец соединяются с ближайшими перекрёстками напрямик:
    /// если село стоит в стороне от дороги, путник доходит до него через степь.
    func route(from start: GeoPoint, to end: GeoPoint) -> RoadPath? {
        guard let s = nearestNode(start), let t = nearestNode(end) else { return nil }
        var dist = Array(repeating: Double.infinity, count: nodes.count)
        var prev = Array(repeating: (node: -1, edge: -1), count: nodes.count)
        var heap = MinHeap()
        let goal = nodes[t]
        dist[s] = 0
        heap.push((Geo.distanceKm(nodes[s], goal), s))
        while let (_, u) = heap.pop() {
            if u == t { break }
            let du = dist[u]
            for (edge, v) in adjacency[u] {
                let nd = du + edges[edge].km
                if nd < dist[v] {
                    dist[v] = nd
                    prev[v] = (u, edge)
                    heap.push((nd + Geo.distanceKm(nodes[v], goal), v))
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
            points.append(contentsOf: forward ? e.geometry : e.geometry.reversed())
            points.append(nodes[forward ? e.b : e.a])
        }
        points.append(end)
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
