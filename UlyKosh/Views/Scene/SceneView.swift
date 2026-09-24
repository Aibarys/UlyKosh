import SwiftUI

enum Terrain: String, Codable, Hashable {
    case river, ruins, mountains, desert, ford, mausoleum, pasture

    var symbol: String {
        switch self {
        case .river, .ford: return "water.waves"
        case .ruins: return "building.columns"
        case .mountains: return "mountain.2"
        case .desert: return "sun.max"
        case .mausoleum: return "building"
        case .pasture: return "leaf"
        }
    }
}

enum SceneWeather: String, Codable, Hashable { case clear, snow, sand }

/// Силуэтный пейзаж: градиентное небо, дальний план, чёрная земля, фигуры каравана.
struct SceneView: View {
    let terrain: Terrain
    var phase: SkyPhase = .current()
    var season: Season = .current()
    var weather: SceneWeather = .clear
    var showCaravan = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let ground = TerrainProfile.ground(terrain)

                ZStack {
                    LinearGradient(colors: phase.colors(for: season), startPoint: .top, endPoint: .bottom)
                    if phase == .night {
                        StarField(time: time)
                    } else {
                        Clouds(time: time, phase: phase)
                    }
                    if let haze = phase.haze(for: season) {
                        LinearGradient(colors: [.clear, haze], startPoint: .top, endPoint: .bottom)
                    }
                    Color(red: 0.72, green: 0.50, blue: 0.20).opacity(weather == .sand ? 0.35 : 0)
                    Color(white: 0.65).opacity(weather == .snow ? 0.35 : 0)

                    TerrainShape(profile: TerrainProfile.far(terrain))
                        .fill(phase.farColor(for: season))

                    TerrainShape(profile: ground)
                        .fill(phase.groundColor(for: season))

                    if terrain == .river || terrain == .ford {
                        let top = terrain == .ford ? 0.88 : 0.91
                        Rectangle()
                            .fill(Color(red: 0.05, green: 0.12, blue: 0.18))
                            .frame(height: h * (1 - top))
                            .position(x: w / 2, y: h * (top + (1 - top) / 2))
                    }

                    StructuresShape(terrain: terrain).fill(Color.black)

                    ForEach(figures) { figure in
                        let motion = figure.motion(at: time)
                        let slope = Self.slopeDegrees(ground, at: figure.t, width: w, height: h)
                        PictogramView(kind: figure.icon, size: figure.size, tint: .black)
                            .scaleEffect(x: figure.flip ? -1 : 1)
                            .rotationEffect(.degrees(motion.tilt + slope), anchor: .bottom)
                            .position(x: w * figure.t, y: h * ground(figure.t) - figure.size * 0.5 + 2 + motion.lift)
                    }

                    if weather == .snow {
                        Particles(time: time, color: .white.opacity(0.8), fall: 0.07, drift: 0.02, count: 70)
                            .transition(.opacity)
                    } else if season == .winter {
                        Particles(time: time, color: .white.opacity(0.55), fall: 0.03, drift: 0.01, count: 25)
                    }
                    if weather == .sand {
                        Particles(time: time, color: Color(red: 0.85, green: 0.65, blue: 0.35).opacity(0.7), fall: 0.02, drift: 0.45, count: 90)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 1.2), value: weather)
            }
        }
        .clipped()
    }

    /// Уклон земли под фигурой в градусах, чтобы она стояла вдоль склона, а не висела над ним.
    private static func slopeDegrees(_ ground: (Double) -> Double, at t: Double, width: CGFloat, height: CGFloat) -> Double {
        let eps = 0.012
        let dy = (ground(min(1, t + eps)) - ground(max(0, t - eps))) * Double(height)
        let dx = 2 * eps * Double(width)
        let degrees = atan2(dy, dx) * 180 / .pi
        return max(-16, min(16, degrees))
    }

    private struct Figure: Identifiable {
        enum Motion { case still, sway }

        let id = UUID()
        let t: Double
        let icon: Pictogram
        let size: CGFloat
        var flip = false
        var motion: Motion = .still

        /// Деревья и камыш чуть наклоняются на ветру, животные стоят неподвижно.
        func motion(at time: Double) -> (lift: CGFloat, tilt: Double) {
            switch motion {
            case .still:
                return (0, 0)
            case .sway:
                return (0, sin(time * 0.9 + t * 37) * 1.6)
            }
        }
    }

    private var figures: [Figure] {
        var list: [Figure] = []
        switch terrain {
        case .river:
            list += [Figure(t: 0.10, icon: .tree, size: 48, motion: .sway), Figure(t: 0.20, icon: .tree, size: 34, motion: .sway)]
        case .ruins:
            list += [Figure(t: 0.95, icon: .tree, size: 40, motion: .sway)]
        case .mountains:
            list += [Figure(t: 0.07, icon: .spruce, size: 38, motion: .sway), Figure(t: 0.13, icon: .spruce, size: 28, motion: .sway)]
        case .desert:
            list += [Figure(t: 0.86, icon: .saiga, size: 18, flip: true), Figure(t: 0.92, icon: .saiga, size: 14, flip: true)]
        case .ford:
            list += [Figure(t: 0.14, icon: .reeds, size: 30, motion: .sway), Figure(t: 0.21, icon: .reeds, size: 24, motion: .sway)]
        case .mausoleum:
            break
        case .pasture:
            list += [Figure(t: 0.08, icon: .horse, size: 20, flip: true), Figure(t: 0.15, icon: .horse, size: 16, flip: true),
                     Figure(t: 0.70, icon: .tree, size: 34, motion: .sway)]
        }
        if showCaravan {
            // Начало каравана на ровном участке; впереди всадник (это вы), за ним верблюды, позади овцы.
            let start: Double
            switch terrain {
            case .ruins: start = 0.58
            case .pasture: start = 0.30
            case .mausoleum: start = 0.10
            default: start = 0.36
            }
            list += [
                Figure(t: start, icon: .sheep, size: 13),
                Figure(t: start + 0.03, icon: .sheep, size: 14),
                Figure(t: start + 0.09, icon: .camel, size: 27),
                Figure(t: start + 0.16, icon: .camel, size: 30),
                Figure(t: start + 0.25, icon: .rider, size: 32)
            ]
        }
        return list
    }
}

enum TerrainProfile {
    /// Линия земли: доля высоты сцены в зависимости от положения по ширине (0...1).
    static func ground(_ terrain: Terrain) -> (Double) -> Double {
        switch terrain {
        case .river: return { 0.80 + 0.015 * sin($0 * 7) }
        case .ruins: return { x in
            if x < 0.24 { return 0.66 }
            if x < 0.52 {
                let f = (x - 0.24) / 0.28
                return 0.66 + (0.5 - 0.5 * cos(f * .pi)) * 0.15
            }
            return 0.81 + 0.01 * sin(x * 12)
        }
        case .mountains: return { 0.70 + 0.10 * $0 + 0.02 * sin($0 * 9) }
        case .desert: return { 0.82 + 0.03 * sin($0 * 4 + 1) }
        case .ford: return { 0.84 + 0.005 * sin($0 * 20) }
        case .mausoleum: return { 0.80 + 0.01 * sin($0 * 7) }
        case .pasture: return { 0.74 + 0.06 * sin($0 * 3.5 + 0.5) }
        }
    }

    static func far(_ terrain: Terrain) -> (Double) -> Double {
        switch terrain {
        case .mountains:
            let peaks: [(Double, Double)] = [(0, 0.60), (0.10, 0.46), (0.20, 0.56), (0.33, 0.36), (0.45, 0.52), (0.56, 0.42), (0.68, 0.58), (0.80, 0.44), (0.92, 0.56), (1, 0.50)]
            return { piecewise($0, peaks) }
        case .desert: return { 0.74 + 0.02 * sin($0 * 3) }
        case .ford: return { 0.70 + 0.03 * sin($0 * 4 + 1) }
        case .mausoleum: return { 0.68 + 0.04 * sin($0 * 4) }
        case .ruins: return { 0.68 + 0.04 * sin($0 * 5 + 2) }
        case .river, .pasture: return { 0.66 + 0.05 * sin($0 * 5 + 2) }
        }
    }

    private static func piecewise(_ x: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0.6 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 1..<points.count where x <= points[i].0 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
        return last.1
    }
}

struct TerrainShape: Shape {
    let profile: (Double) -> Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 140
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: rect.minX + rect.width * t, y: rect.minY + rect.height * profile(t)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Постройки на переднем плане: руины, мавзолей, юрты.
struct StructuresShape: Shape {
    let terrain: Terrain

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let ground = TerrainProfile.ground(terrain)

        func yurt(at t: Double, width: CGFloat) {
            let baseY = h * ground(t)
            let x = w * t - width / 2
            let wall = width * 0.32
            path.addRect(CGRect(x: x, y: baseY - wall, width: width, height: wall))
            path.addEllipse(in: CGRect(x: x, y: baseY - wall - width * 0.42, width: width, height: width * 0.84))
        }

        switch terrain {
        case .ruins:
            let top = h * 0.66
            path.addRect(CGRect(x: w * 0.04, y: top - h * 0.08, width: w * 0.18, height: h * 0.09))
            path.addRect(CGRect(x: w * 0.08, y: top - h * 0.15, width: w * 0.05, height: h * 0.08))
            for i in 0..<4 {
                path.addRect(CGRect(x: w * (0.05 + Double(i) * 0.045), y: top - h * 0.10, width: w * 0.02, height: h * 0.025))
            }
        case .mausoleum:
            let baseY = h * ground(0.67)
            let bw = w * 0.20
            let x = w * 0.67 - bw / 2
            path.addRect(CGRect(x: x, y: baseY - h * 0.11, width: bw, height: h * 0.12))
            path.addEllipse(in: CGRect(x: x + bw * 0.1, y: baseY - h * 0.11 - bw * 0.36, width: bw * 0.8, height: bw * 0.72))
            path.addRect(CGRect(x: x + bw * 0.44, y: baseY - h * 0.11 - bw * 0.36 - h * 0.03, width: bw * 0.12, height: h * 0.04))
        case .river:
            yurt(at: 0.80, width: w * 0.11)
            yurt(at: 0.91, width: w * 0.09)
        case .pasture:
            yurt(at: 0.85, width: w * 0.10)
            yurt(at: 0.94, width: w * 0.08)
        default:
            break
        }
        return path
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

struct StarField: View {
    let time: Double

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 42)
            for i in 0..<80 {
                let x = Double.random(in: 0...1, using: &rng) * size.width
                let y = Double.random(in: 0...0.62, using: &rng) * size.height
                let r = Double.random(in: 0.4...1.3, using: &rng)
                let base = Double.random(in: 0.3...0.9, using: &rng)
                let twinkle = 0.65 + 0.35 * sin(time * (0.8 + Double(i % 7) * 0.3) + Double(i))
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(base * twinkle)))
            }
        }
    }
}

/// Несколько мягких облаков, которые медленно плывут слева направо.
struct Clouds: View {
    let time: Double
    let phase: SkyPhase

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 11)
            let tint: Color = phase == .day ? .white : Color(red: 1, green: 0.85, blue: 0.7)
            for _ in 0..<4 {
                let x0 = Double.random(in: 0...1, using: &rng)
                let y = Double.random(in: 0.08...0.42, using: &rng) * size.height
                let scale = Double.random(in: 0.6...1.2, using: &rng)
                let speed = Double.random(in: 0.006...0.012, using: &rng)
                let alpha = Double.random(in: 0.10...0.22, using: &rng)
                let span = size.width + 200
                let x = ((x0 * span + time * speed * size.width).truncatingRemainder(dividingBy: span)) - 100
                var cloud = Path()
                cloud.addEllipse(in: CGRect(x: x, y: y, width: 90 * scale, height: 22 * scale))
                cloud.addEllipse(in: CGRect(x: x + 25 * scale, y: y - 12 * scale, width: 60 * scale, height: 30 * scale))
                cloud.addEllipse(in: CGRect(x: x + 50 * scale, y: y - 4 * scale, width: 55 * scale, height: 22 * scale))
                context.fill(cloud, with: .color(tint.opacity(alpha)))
            }
        }
    }
}

/// Снег или песок: точки, которые медленно летят по сцене.
struct Particles: View {
    let time: Double
    let color: Color
    let fall: Double
    let drift: Double
    let count: Int

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 7)
            for _ in 0..<count {
                let x0 = Double.random(in: 0...1, using: &rng)
                let y0 = Double.random(in: 0...1, using: &rng)
                let speed = Double.random(in: 0.6...1.4, using: &rng)
                let r = Double.random(in: 0.8...2.0, using: &rng)
                let y = wrap(y0 + time * fall * speed) * size.height
                let x = wrap(x0 + time * drift * speed) * size.width
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }

    private func wrap(_ v: Double) -> Double {
        let f = v.truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }
}
