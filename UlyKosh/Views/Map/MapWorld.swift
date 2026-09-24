import SwiftUI

/// Сырые геоданные из kazakhstan-map.json (Natural Earth + дорисовка).
struct MapData: Decodable {
    struct Water: Decodable { let name: String?; let label: [Double]?; let rings: [[[Double]]] }
    struct River: Decodable { let name: String?; let width: Double; let label: [Double]?; let lines: [[[Double]]] }
    struct SymbolGroup: Decodable { let kind: String; let points: [[Double]] }
    struct Label: Decodable { let text: String; let kind: String; let at: [Double]; let angle: Double }
    struct City: Decodable { let name: String; let at: [Double]; let capital: Bool; let rank: Int }
    struct Historic: Decodable { let name: String; let at: [Double] }

    let border: [[[Double]]]
    let water: [Water]
    let rivers: [River]
    let symbols: [SymbolGroup]
    let labels: [Label]
    let cities: [City]
    let historic: [Historic]

    static func load() -> MapData? {
        guard let url = Bundle.main.url(forResource: "kazakhstan-map", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MapData.self, from: data)
    }
}

/// Коническая равноугольная проекция Ламберта: параллели не прямые, карта выглядит как атлас.
struct MapProjection {
    private let n: Double
    private let f: Double
    private let rho0: Double
    private let lambda0 = 67.0 * Double.pi / 180
    private let unit = 1000.0

    init() {
        let phi1 = 43.0 * Double.pi / 180, phi2 = 53.0 * Double.pi / 180, phi0 = 48.0 * Double.pi / 180
        n = log(cos(phi1) / cos(phi2)) / log(tan(Double.pi / 4 + phi2 / 2) / tan(Double.pi / 4 + phi1 / 2))
        f = cos(phi1) * pow(tan(Double.pi / 4 + phi1 / 2), n) / n
        rho0 = f / pow(tan(Double.pi / 4 + phi0 / 2), n)
    }

    func project(lon: Double, lat: Double) -> CGPoint {
        let phi = lat * Double.pi / 180, lambda = lon * Double.pi / 180
        let rho = f / pow(tan(Double.pi / 4 + phi / 2), n)
        let theta = n * (lambda - lambda0)
        return CGPoint(x: rho * sin(theta) * unit, y: -(rho0 - rho * cos(theta)) * unit)
    }

    func project(_ p: GeoPoint) -> CGPoint { project(lon: p.lon, lat: p.lat) }
}

/// Геоданные, уже спроецированные в «мировые» координаты. Строится один раз.
final class MapWorld {
    enum SymbolKind: String { case range, hills, plateau, desert }
    struct Water { let path: Path; let bounds: CGRect; let name: String?; let label: CGPoint? }
    struct River { let path: Path; let width: Double; let name: String?; let label: CGPoint? }
    struct Symbols { let kind: SymbolKind; let points: [CGPoint] }
    struct Label { let text: String; let kind: String; let at: CGPoint; let angle: Double }
    struct City { let name: String; let at: CGPoint; let capital: Bool; let rank: Int }
    struct Historic { let name: String; let at: CGPoint }

    static let shared: MapWorld? = MapData.load().map { MapWorld(data: $0) }

    let projection: MapProjection
    let border: Path
    let bounds: CGRect
    let waters: [Water]
    let rivers: [River]
    let symbols: [Symbols]
    let labels: [Label]
    let cities: [City]
    let historic: [Historic]
    /// Километров в одной мировой единице (по параллели 48°).
    let kmPerUnit: Double

    init(data: MapData) {
        let projection = MapProjection()
        func pt(_ c: [Double]) -> CGPoint { projection.project(lon: c[0], lat: c[1]) }
        func path(_ polylines: [[[Double]]], closed: Bool) -> Path {
            var p = Path()
            for line in polylines {
                guard let first = line.first else { continue }
                p.move(to: pt(first))
                for c in line.dropFirst() { p.addLine(to: pt(c)) }
                if closed { p.closeSubpath() }
            }
            return p
        }

        self.projection = projection
        border = path(data.border, closed: true)
        bounds = border.boundingRect
        waters = data.water.map { w in
            let p = path(w.rings, closed: true)
            return Water(path: p, bounds: p.boundingRect, name: w.name, label: w.label.map(pt))
        }
        rivers = data.rivers.map { River(path: path($0.lines, closed: false), width: $0.width, name: $0.name, label: $0.label.map(pt)) }
        symbols = data.symbols.compactMap { g in
            guard let kind = SymbolKind(rawValue: g.kind) else { return nil }
            return Symbols(kind: kind, points: g.points.map(pt))
        }
        labels = data.labels.map { Label(text: $0.text, kind: $0.kind, at: pt($0.at), angle: $0.angle) }
        cities = data.cities.map { City(name: $0.name, at: pt($0.at), capital: $0.capital, rank: $0.rank) }
        historic = data.historic.map { Historic(name: $0.name, at: pt($0.at)) }

        let a = projection.project(lon: 67, lat: 48), b = projection.project(lon: 68, lat: 48)
        kmPerUnit = 74.6 / Double(hypot(b.x - a.x, b.y - a.y))
    }
}
