import SwiftUI

enum Terrain: String, Codable, Hashable {
    case river, ruins, mountains, desert, ford, mausoleum, pasture, steppe, town

    var symbol: String {
        switch self {
        case .river, .ford: return "water.waves"
        case .ruins: return "building.columns"
        case .mountains: return "mountain.2"
        case .desert: return "sun.max"
        case .mausoleum: return "building"
        case .pasture, .steppe: return "leaf"
        case .town: return "house"
        }
    }
}

enum SceneWeather: String, Codable, Hashable { case clear, snow, sand, rain, clouds }

/// Силуэтный пейзаж: градиентное небо, дальний план, чёрная земля, фигуры каравана.
struct SceneView: View {
    let terrain: Terrain
    var phase: SkyPhase = .current()
    var season: Season = .current()
    var weather: SceneWeather = .clear
    var showCaravan = true
    /// Подробная погода (реальная из WeatherKit). Если не задана, берётся погода испытания.
    var atmosphere: Atmosphere? = nil

    private var air: Atmosphere { atmosphere ?? Atmosphere(event: weather) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let ground = TerrainProfile.ground(terrain)
                let air = self.air
                let flash = LightningLayer.flash(air.lightning, at: time).amount

                ZStack {
                    // Небо
                    LinearGradient(colors: phase.colors(for: season), startPoint: .top, endPoint: .bottom)
                    SkyOvercast(atmosphere: air, phase: phase)
                    if phase == .night {
                        StarField(time: time).opacity(max(0, 1 - air.cloudCover * 1.3))
                    }
                    SkyBody(atmosphere: air, phase: phase, time: time)
                    CloudLayer(atmosphere: air, phase: phase, time: time)
                    LightningLayer(atmosphere: air, time: time, groundY: h * 0.78)
                    if let haze = phase.haze(for: season) {
                        LinearGradient(colors: [.clear, haze], startPoint: .top, endPoint: .bottom)
                    }
                    if air.veil != .none { VeilLayer(atmosphere: air, phase: phase) }

                    // Дальний план и туман за ним
                    TerrainShape(profile: TerrainProfile.far(terrain))
                        .fill(phase.farColor(for: season))
                    if air.fog > 0 { FogLayer(amount: air.fog, phase: phase, time: time) }

                    // Земля
                    TerrainShape(profile: ground)
                        .fill(phase.groundColor(for: season))
                    if air.snowCover && season != .winter {
                        SnowCapShape(profile: ground)
                            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                    if air.glaze {
                        SnowCapShape(profile: ground)
                            .stroke(Color(red: 0.8, green: 0.92, blue: 1).opacity(0.7), lineWidth: 1.5)
                    }

                    if terrain == .river || terrain == .ford {
                        WaterView(top: terrain == .ford ? 0.88 : 0.91, phase: phase, time: time, rain: air.precipitation != .none, wind: air.wind)
                    }

                    StructuresShape(terrain: terrain).fill(Color.black)
                    YurtCutoutsShape(terrain: terrain).fill(phase.farColor(for: season))

                    ForEach(figures) { figure in
                        let motion = figure.motion(at: time, wind: air.wind)
                        let slope = Self.slopeDegrees(ground, at: figure.t, width: w, height: h)
                        PictogramView(kind: figure.icon, size: figure.size, tint: .black)
                            .scaleEffect(x: figure.flip ? -1 : 1)
                            .rotationEffect(.degrees(motion.tilt + slope), anchor: .bottom)
                            .position(x: w * figure.t, y: h * ground(figure.t) - figure.size * 0.5 + 2 + motion.lift)
                    }

                    // Передний план погоды
                    if air.fog > 0.2 { FogLayer(amount: air.fog, phase: phase, time: time, near: true) }
                    if air.precipitation != .none {
                        PrecipitationLayer(atmosphere: air, time: time)
                    } else if season == .winter {
                        Particles(time: time, color: .white.opacity(0.55), fall: 0.03, drift: 0.01, count: 25)
                    }
                    if air.blowingSnow > 0 || air.blowingDust > 0 {
                        GroundDriftLayer(snow: air.blowingSnow, dust: air.blowingDust, wind: air.wind, time: time)
                    }
                    if air.precipitation == .none && air.blowingDust == 0 && air.blowingSnow == 0 {
                        WindStreakLayer(wind: air.wind, time: time)
                    }
                    if air.heat { HeatShimmerLayer(time: time) }
                    if air.frost { FrostSparkleLayer(time: time) }
                    if flash > 0 {
                        Color(red: 0.9, green: 0.92, blue: 1).opacity(flash * 0.35).allowsHitTesting(false)
                    }
                }
                .animation(.easeInOut(duration: 1.2), value: air)
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

        /// Деревья и камыш наклоняются на ветру: чем сильнее ветер, тем ниже и быстрее. Животные стоят.
        func motion(at time: Double, wind: Double = 0.1) -> (lift: CGFloat, tilt: Double) {
            switch motion {
            case .still:
                return (0, 0)
            case .sway:
                let lean = wind * 7
                let amplitude = 1.6 + wind * 4
                return (0, lean + sin(time * (0.9 + wind * 2.2) + t * 37) * amplitude)
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
        case .steppe:
            list += [Figure(t: 0.10, icon: .reeds, size: 18, motion: .sway), Figure(t: 0.16, icon: .reeds, size: 14, motion: .sway),
                     Figure(t: 0.78, icon: .reeds, size: 16, motion: .sway), Figure(t: 0.90, icon: .saiga, size: 13, flip: true)]
        case .town:
            list += [Figure(t: 0.08, icon: .tree, size: 30, motion: .sway), Figure(t: 0.15, icon: .tree, size: 24, motion: .sway)]
        }
        if showCaravan {
            // Путник идёт по ровному месту, вправо, к следующей стоянке.
            let at: Double
            switch terrain {
            case .ruins: at = 0.68
            case .pasture: at = 0.42
            case .mausoleum: at = 0.30
            case .town: at = 0.36
            default: at = 0.48
            }
            list.append(Figure(t: at, icon: .walker, size: 40))
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
        case .steppe: return { 0.81 + 0.012 * sin($0 * 5 + 1) }
        case .town: return { 0.82 + 0.006 * sin($0 * 9) }
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
        case .steppe: return { 0.75 + 0.015 * sin($0 * 3 + 2) + 0.03 * exp(-pow(($0 - 0.3) * 9, 2)) }
        case .town: return { 0.74 + 0.02 * sin($0 * 4) }
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

/// Просветы в юртах: дверь и пояс на стыке стены и купола.
struct YurtCutoutsShape: Shape {
    let terrain: Terrain

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let ground = TerrainProfile.ground(terrain)
        for (t, width) in StructuresShape.yurts(for: terrain, w: w) {
            let baseY = StructuresShape.yurtBase(ground, at: t, width: width, w: w, h: h)
            let cx = w * t
            let wallH = width * 0.30
            let visibleBase = h * ground(t)
            let doorW = width * 0.16, doorH = wallH * 0.72
            var door = Path()
            door.move(to: CGPoint(x: cx - doorW / 2, y: visibleBase))
            door.addLine(to: CGPoint(x: cx - doorW / 2, y: visibleBase - doorH * 0.8))
            door.addQuadCurve(to: CGPoint(x: cx + doorW / 2, y: visibleBase - doorH * 0.8),
                              control: CGPoint(x: cx, y: visibleBase - doorH * 1.15))
            door.addLine(to: CGPoint(x: cx + doorW / 2, y: visibleBase))
            door.closeSubpath()
            path.addPath(door)
            // тонкий пояс на карнизе
            path.addRect(CGRect(x: cx - width / 2 + width * 0.03, y: baseY - wallH - width * 0.012, width: width * 0.94, height: width * 0.014))
        }
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

        /// Юрта: цилиндрическая стена кереге, конический купол с плавным перегибом,
        /// шанырак с дымком, дверь и просветы решётки в стене.
        func yurt(at t: Double, width: CGFloat, door: Bool = true) {
            let baseY = Self.yurtBase(ground, at: t, width: width, w: w, h: h)
            let cx = w * t
            let r = width / 2
            let wallH = width * 0.30
            let domeH = width * 0.34
            let wallTop = baseY - wallH
            let ringR = width * 0.09

            var body = Path()
            body.move(to: CGPoint(x: cx - r, y: baseY))
            body.addLine(to: CGPoint(x: cx - r, y: wallTop))
            body.addLine(to: CGPoint(x: cx - r * 1.04, y: wallTop))
            // левый скат купола: круто у карниза, положе к шаныраку
            body.addQuadCurve(to: CGPoint(x: cx - ringR, y: wallTop - domeH),
                              control: CGPoint(x: cx - r * 0.72, y: wallTop - domeH * 0.78))
            body.addLine(to: CGPoint(x: cx + ringR, y: wallTop - domeH))
            body.addQuadCurve(to: CGPoint(x: cx + r * 1.04, y: wallTop),
                              control: CGPoint(x: cx + r * 0.72, y: wallTop - domeH * 0.78))
            body.addLine(to: CGPoint(x: cx + r, y: wallTop))
            body.addLine(to: CGPoint(x: cx + r, y: baseY))
            body.closeSubpath()
            path.addPath(body)

            // шанырак: кольцо и крестовина над куполом
            let ringY = wallTop - domeH - ringR * 0.5
            path.addEllipse(in: CGRect(x: cx - ringR, y: ringY - ringR * 0.55, width: ringR * 2, height: ringR * 1.1))
            path.addRect(CGRect(x: cx - width * 0.012, y: ringY - ringR * 1.35, width: width * 0.024, height: ringR * 1.35))

            // просветы: дверь и полосы бау на куполе делаем отдельно, вычитанием не получится в одном Path,
            // поэтому рисуем их поверх цветом неба в StructuresOverlay.
            _ = door
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
        case .river, .pasture:
            for (t, width) in Self.yurts(for: terrain, w: w) { yurt(at: t, width: width) }
        case .town:
            // Низкие дома с двускатными крышами, водонапорная башня и минарет
            let houses: [(Double, CGFloat, CGFloat)] = [(0.60, 0.07, 0.05), (0.69, 0.09, 0.065), (0.80, 0.06, 0.045), (0.88, 0.08, 0.06), (0.97, 0.07, 0.05)]
            for (t, width, height) in houses {
                let baseY = h * ground(t) + 2
                let x = w * t - w * width / 2
                let wallH = h * height
                path.addRect(CGRect(x: x, y: baseY - wallH, width: w * width, height: wallH))
                var roof = Path()
                roof.move(to: CGPoint(x: x - 3, y: baseY - wallH))
                roof.addLine(to: CGPoint(x: x + w * width / 2, y: baseY - wallH - h * height * 0.7))
                roof.addLine(to: CGPoint(x: x + w * width + 3, y: baseY - wallH))
                roof.closeSubpath()
                path.addPath(roof)
            }
            let towerX = w * 0.745, towerBase = h * ground(0.745) + 2
            path.addRect(CGRect(x: towerX - 2, y: towerBase - h * 0.17, width: 4, height: h * 0.17))
            path.addEllipse(in: CGRect(x: towerX - 9, y: towerBase - h * 0.22, width: 18, height: h * 0.06))
            let minX = w * 0.93, minBase = h * ground(0.93) + 2
            path.addRect(CGRect(x: minX - 3, y: minBase - h * 0.2, width: 6, height: h * 0.2))
            var cap = Path()
            cap.move(to: CGPoint(x: minX - 4, y: minBase - h * 0.2))
            cap.addLine(to: CGPoint(x: minX, y: minBase - h * 0.25))
            cap.addLine(to: CGPoint(x: minX + 4, y: minBase - h * 0.2))
            cap.closeSubpath()
            path.addPath(cap)
        default:
            break
        }
        return path
    }

    /// Основание юрты: ниже самой низкой точки земли под ней, чтобы оба края уходили в грунт.
    static func yurtBase(_ ground: (Double) -> Double, at t: Double, width: CGFloat, w: CGFloat, h: CGFloat) -> CGFloat {
        let half = Double(width / 2 / w)
        let lowest = max(ground(max(0, t - half)), ground(t), ground(min(1, t + half)))
        return h * lowest + width * 0.06
    }

    /// Положение и ширина юрт по местности, общие для силуэта и просветов.
    static func yurts(for terrain: Terrain, w: CGFloat) -> [(Double, CGFloat)] {
        switch terrain {
        case .river: return [(0.80, w * 0.13), (0.93, w * 0.10)]
        case .pasture: return [(0.86, w * 0.12), (0.96, w * 0.095)]
        default: return []
        }
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
    var count = 4
    var opacity: Double? = nil

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 11)
            let tint: Color = opacity != nil ? Color(white: 0.85) : (phase == .day ? .white : Color(red: 1, green: 0.85, blue: 0.7))
            for _ in 0..<count {
                let x0 = Double.random(in: 0...1, using: &rng)
                let y = Double.random(in: 0.08...0.42, using: &rng) * size.height
                let scale = Double.random(in: 0.6...1.2, using: &rng)
                let speed = Double.random(in: 0.006...0.012, using: &rng)
                let alpha = opacity ?? Double.random(in: 0.10...0.22, using: &rng)
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


/// Косые штрихи дождя.
struct Rain: View {
    let time: Double

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 23)
            var streaks = Path()
            for _ in 0..<120 {
                let x0 = Double.random(in: 0...1, using: &rng)
                let y0 = Double.random(in: 0...1, using: &rng)
                let speed = Double.random(in: 0.8...1.3, using: &rng)
                let len = Double.random(in: 8...14, using: &rng)
                let y = (y0 + time * 0.9 * speed).truncatingRemainder(dividingBy: 1) * size.height
                let x = (x0 + time * 0.12 * speed).truncatingRemainder(dividingBy: 1) * size.width
                streaks.move(to: CGPoint(x: x, y: y))
                streaks.addLine(to: CGPoint(x: x - len * 0.25, y: y + len))
            }
            context.stroke(streaks, with: .color(Color(white: 0.85).opacity(0.45)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}


/// Линия по верху земли: снежная шапка или ледяная корка.
struct SnowCapShape: Shape {
    let profile: (Double) -> Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0...140 {
            let t = Double(i) / 140
            let p = CGPoint(x: rect.minX + rect.width * t, y: rect.minY + rect.height * profile(t) + 1.5)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        return path
    }
}

/// Река на переднем плане: отражённое небо, блик по кромке, рябь, круги от капель.
struct WaterView: View {
    let top: Double
    let phase: SkyPhase
    let time: Double
    var rain = false
    var wind: Double = 0.1

    var body: some View {
        Canvas { ctx, size in
            let y0 = size.height * top
            let rect = CGRect(x: 0, y: y0, width: size.width, height: size.height - y0)
            let sky = phase == .night ? Color(red: 0.08, green: 0.12, blue: 0.18) : Color(red: 0.32, green: 0.44, blue: 0.52)
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [sky.opacity(0.9), Color(red: 0.04, green: 0.08, blue: 0.12)]),
                                                      startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            ctx.fill(Path(CGRect(x: 0, y: y0, width: size.width, height: 1.2)), with: .color(Color.white.opacity(0.25)))
            var rng = SeededGenerator(seed: 5)
            var ripples = Path()
            for _ in 0..<26 {
                let x0 = Double.random(in: 0...1, using: &rng)
                let yy = Double.random(in: 0.15...0.9, using: &rng)
                let len = Double.random(in: 10...30, using: &rng)
                let x = ((x0 + time * (0.01 + wind * 0.04)).truncatingRemainder(dividingBy: 1)) * size.width
                let y = y0 + rect.height * yy
                ripples.move(to: CGPoint(x: x, y: y))
                ripples.addLine(to: CGPoint(x: x + len, y: y))
            }
            ctx.stroke(ripples, with: .color(Color.white.opacity(0.14)), lineWidth: 1)
            if rain {
                var drops = Path()
                for i in 0..<14 {
                    let cycle = (time * 0.9 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                    var r2 = SeededGenerator(seed: UInt64(200 + i) &+ UInt64(time * 0.9 + Double(i) * 0.37))
                    let x = Double.random(in: 0...1, using: &r2) * size.width
                    let y = y0 + rect.height * Double.random(in: 0.2...0.85, using: &r2)
                    let r = 1 + cycle * 7
                    drops.addEllipse(in: CGRect(x: x - r, y: y - r * 0.3, width: r * 2, height: r * 0.6))
                }
                ctx.stroke(drops, with: .color(Color.white.opacity(0.18)), lineWidth: 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}
