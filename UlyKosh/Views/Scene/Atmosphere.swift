import SwiftUI
import WeatherKit

/// Погода на сцене, разложенная на слои. Строится из состояния WeatherKit или из погоды испытания.
struct Atmosphere: Equatable {
    enum Precipitation: Equatable {
        case none, drizzle, lightRain, rain, heavyRain
        case flurries, snow, heavySnow
        case sleet, freezingDrizzle, freezingRain, hail
    }

    enum Veil: Equatable { case none, haze, smoke, dust }

    /// Доля неба под облаками, 0…1.
    var cloudCover: Double = 0.25
    /// Насколько гроза или ненастье затемняют небо, 0…1.
    var darkness: Double = 0
    var precipitation: Precipitation = .none
    /// Сила ветра, 0…1: наклон осадков, скорость облаков, качание деревьев.
    var wind: Double = 0.1
    /// Частота и яркость молний, 0…1.
    var lightning: Double = 0
    /// Туман у земли, 0…1.
    var fog: Double = 0
    var veil: Veil = .none
    var veilAmount: Double = 0
    /// Позёмка у земли.
    var blowingSnow: Double = 0
    var blowingDust: Double = 0
    /// Марево от жары и иней от мороза.
    var heat = false
    var frost = false
    /// Солнце видно сквозь осадки (слепой дождь, снег при солнце).
    var sunThrough = false
    /// Снег лежит на земле и постройках.
    var snowCover = false
    /// Ледяная корка после ледяного дождя.
    var glaze = false

    static let fair = Atmosphere()

    var isSnowy: Bool { [.flurries, .snow, .heavySnow, .sleet].contains(precipitation) }

    // MARK: - Из погоды испытания

    init() {}

    init(event: SceneWeather) {
        switch event {
        case .clear: self = .fair
        case .clouds: cloudCover = 0.85; darkness = 0.1
        case .rain: cloudCover = 1; darkness = 0.3; precipitation = .rain; wind = 0.3
        case .snow: cloudCover = 1; darkness = 0.15; precipitation = .snow; wind = 0.5; snowCover = true
        case .sand: cloudCover = 0.3; veil = .dust; veilAmount = 0.55; blowingDust = 1; wind = 0.85
        }
    }

    // MARK: - Из WeatherKit

    /// - Parameters:
    ///   - cloudCover: реальная облачность 0…1, если известна.
    ///   - windKmh: реальная скорость ветра.
    init(condition: WeatherCondition, cloudCover realCover: Double? = nil, windKmh: Double? = nil) {
        switch condition {
        case .clear: cloudCover = 0.05
        case .mostlyClear: cloudCover = 0.2
        case .partlyCloudy: cloudCover = 0.45
        case .mostlyCloudy: cloudCover = 0.7
        case .cloudy: cloudCover = 0.95; darkness = 0.05
        case .foggy: cloudCover = 0.8; fog = 1
        case .haze: cloudCover = 0.3; veil = .haze; veilAmount = 0.5
        case .smoky: cloudCover = 0.4; veil = .smoke; veilAmount = 0.65; darkness = 0.15
        case .blowingDust: cloudCover = 0.3; veil = .dust; veilAmount = 0.5; blowingDust = 1; wind = 0.85
        case .breezy: cloudCover = 0.35; wind = 0.5
        case .windy: cloudCover = 0.45; wind = 0.85
        case .drizzle: cloudCover = 0.9; darkness = 0.1; precipitation = .drizzle; wind = 0.15
        case .rain: cloudCover = 1; darkness = 0.25; precipitation = .rain; wind = 0.3
        case .heavyRain: cloudCover = 1; darkness = 0.45; precipitation = .heavyRain; wind = 0.5
        case .sunShowers: cloudCover = 0.5; precipitation = .lightRain; sunThrough = true; wind = 0.2
        case .isolatedThunderstorms: cloudCover = 0.75; darkness = 0.35; precipitation = .lightRain; lightning = 0.35; wind = 0.35
        case .scatteredThunderstorms: cloudCover = 0.9; darkness = 0.45; precipitation = .rain; lightning = 0.6; wind = 0.45
        case .thunderstorms: cloudCover = 1; darkness = 0.6; precipitation = .heavyRain; lightning = 0.85; wind = 0.5
        case .strongStorms: cloudCover = 1; darkness = 0.75; precipitation = .heavyRain; lightning = 1; wind = 0.9
        case .tropicalStorm: cloudCover = 1; darkness = 0.65; precipitation = .heavyRain; lightning = 0.5; wind = 1
        case .hurricane: cloudCover = 1; darkness = 0.8; precipitation = .heavyRain; lightning = 0.6; wind = 1; fog = 0.3
        case .flurries: cloudCover = 0.7; precipitation = .flurries; wind = 0.2
        case .sunFlurries: cloudCover = 0.45; precipitation = .flurries; sunThrough = true; wind = 0.15
        case .snow: cloudCover = 0.95; darkness = 0.15; precipitation = .snow; wind = 0.25; snowCover = true
        case .heavySnow: cloudCover = 1; darkness = 0.3; precipitation = .heavySnow; wind = 0.4; snowCover = true
        case .blowingSnow: cloudCover = 0.6; precipitation = .flurries; blowingSnow = 1; wind = 0.85; snowCover = true
        case .blizzard: cloudCover = 1; darkness = 0.2; precipitation = .heavySnow; blowingSnow = 1; wind = 1; fog = 0.5; snowCover = true
        case .sleet: cloudCover = 1; darkness = 0.25; precipitation = .sleet; wind = 0.35
        case .wintryMix: cloudCover = 1; darkness = 0.2; precipitation = .sleet; wind = 0.3; snowCover = true
        case .freezingDrizzle: cloudCover = 0.95; darkness = 0.15; precipitation = .freezingDrizzle; glaze = true
        case .freezingRain: cloudCover = 1; darkness = 0.3; precipitation = .freezingRain; glaze = true; wind = 0.25
        case .hail: cloudCover = 1; darkness = 0.45; precipitation = .hail; lightning = 0.3; wind = 0.45
        case .hot: cloudCover = 0.05; heat = true; veil = .haze; veilAmount = 0.2
        case .frigid: cloudCover = 0.1; frost = true
        @unknown default: cloudCover = 0.4
        }
        // Для ясной и облачной погоды верим реальной облачности, в ненастье — описанию.
        if let realCover, [.clear, .mostlyClear, .partlyCloudy, .mostlyCloudy, .cloudy, .breezy, .windy, .hot, .frigid].contains(condition) {
            cloudCover = max(0, min(1, realCover))
        }
        if let windKmh {
            wind = max(wind, min(1, max(0, (windKmh - 8) / 50)))
        }
    }

    /// Все состояния WeatherKit, которые умеет рисовать сцена, в порядке показа в отладке.
    static let allConditions: [WeatherCondition] = [
        .clear, .mostlyClear, .partlyCloudy, .mostlyCloudy, .cloudy, .foggy, .haze, .smoky, .blowingDust,
        .breezy, .windy, .drizzle, .rain, .heavyRain, .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms,
        .thunderstorms, .strongStorms, .tropicalStorm, .hurricane, .flurries, .sunFlurries, .snow, .heavySnow,
        .blowingSnow, .blizzard, .sleet, .wintryMix, .freezingDrizzle, .freezingRain, .hail, .hot, .frigid
    ]
}

// MARK: - Слои неба

/// Затемнение и серость неба по облачности и грозе.
/// При облачности выше ~60% небо закрывает сплошной облачный покров: голубого просвета не остаётся.
struct SkyOvercast: View {
    let atmosphere: Atmosphere
    let phase: SkyPhase

    var body: some View {
        let cover = atmosphere.cloudCover
        // Плавный порог: 0 при 0.55, 1 при 1.0.
        let x = max(0, min(1, (cover - 0.55) / 0.45))
        let deck = x * x * (3 - 2 * x)
        let deckTop: Color
        let deckBottom: Color
        switch phase {
        case .night:
            deckTop = Color(white: 0.08); deckBottom = Color(white: 0.16)
        case .dawn, .dusk:
            deckTop = Color(red: 0.36, green: 0.36, blue: 0.42); deckBottom = Color(red: 0.62, green: 0.56, blue: 0.54)
        case .day:
            if atmosphere.isSnowy {
                deckTop = Color(red: 0.66, green: 0.69, blue: 0.74); deckBottom = Color(red: 0.86, green: 0.87, blue: 0.89)
            } else {
                deckTop = Color(red: 0.5, green: 0.54, blue: 0.6); deckBottom = Color(red: 0.72, green: 0.74, blue: 0.77)
            }
        }
        return ZStack {
            Color(white: phase == .night ? 0.1 : 0.6).opacity(cover * 0.25)
            LinearGradient(colors: [deckTop, deckBottom], startPoint: .top, endPoint: .bottom)
                .opacity(deck * 0.92)
            LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.1), Color(red: 0.16, green: 0.18, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(atmosphere.darkness * 0.78)
            if atmosphere.frost {
                Color(red: 0.75, green: 0.88, blue: 1).opacity(0.18)
            }
            if atmosphere.heat {
                LinearGradient(colors: [.clear, Color(red: 1, green: 0.78, blue: 0.45).opacity(0.3)], startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Солнце днём, луна ночью; прячутся за облаками.
struct SkyBody: View {
    let atmosphere: Atmosphere
    let phase: SkyPhase
    let time: Double

    var body: some View {
        Canvas { ctx, size in
            var visibility = max(0, 1 - atmosphere.cloudCover * 1.15) * (1 - atmosphere.darkness)
            if atmosphere.sunThrough { visibility = max(visibility, 0.7) }
            if atmosphere.veil != .none { visibility *= 1 - atmosphere.veilAmount * 0.4 }
            guard visibility > 0.02 else { return }

            let k = size.height / 470
            let center: CGPoint
            let radius: CGFloat
            let core: Color
            let glow: Color
            switch phase {
            case .day:
                center = CGPoint(x: size.width * 0.74, y: size.height * 0.2)
                radius = (atmosphere.heat ? 30 : 22) * k
                core = atmosphere.frost ? Color(white: 0.97) : Color(red: 1, green: 0.97, blue: 0.86)
                glow = atmosphere.heat ? Color(red: 1, green: 0.85, blue: 0.5) : Color(red: 1, green: 0.95, blue: 0.8)
            case .dawn:
                center = CGPoint(x: size.width * 0.18, y: size.height * 0.6)
                radius = 26 * k
                core = Color(red: 1, green: 0.85, blue: 0.6)
                glow = Color(red: 1, green: 0.62, blue: 0.4)
            case .dusk:
                center = CGPoint(x: size.width * 0.84, y: size.height * 0.58)
                radius = 26 * k
                core = Color(red: 1, green: 0.78, blue: 0.5)
                glow = Color(red: 1, green: 0.5, blue: 0.3)
            case .night:
                center = CGPoint(x: size.width * 0.76, y: size.height * 0.18)
                radius = 14 * k
                core = Color(red: 0.95, green: 0.94, blue: 0.86)
                glow = Color(red: 0.8, green: 0.85, blue: 0.95)
            }
            let haze = atmosphere.veil == .none ? 1.0 : 1 + atmosphere.veilAmount * 1.5
            let glowRadius = radius * (phase == .night ? 3 : 4.5) * haze
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                     with: .radialGradient(Gradient(colors: [glow.opacity(0.45 * visibility), .clear]),
                                           center: center, startRadius: radius * 0.6, endRadius: glowRadius))
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            if phase == .night {
                // Луна: диск с тенью сбоку.
                ctx.drawLayer { layer in
                    layer.opacity = visibility
                    layer.fill(disc, with: .color(core))
                    layer.blendMode = .destinationOut
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - radius + 7 * k, y: center.y - radius - 3 * k, width: radius * 2, height: radius * 2)), with: .color(.black))
                }
            } else {
                ctx.fill(disc, with: .color(core.opacity(visibility * (atmosphere.veil == .none ? 1 : 0.8))))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Облака: количество по облачности, тон по грозе, скорость по ветру.
struct CloudLayer: View {
    let atmosphere: Atmosphere
    let phase: SkyPhase
    let time: Double

    var body: some View {
        Canvas { context, size in
            let cover = atmosphere.cloudCover
            guard cover > 0.02 else { return }
            var rng = SeededGenerator(seed: 11)
            let k = size.height / 470
            let count = Int(3 + cover * 16)
            let speedK = 1 + atmosphere.wind * 5
            let dark = atmosphere.darkness
            let base: Color
            switch phase {
            case .night: base = Color(white: 0.28)
            case .dawn, .dusk: base = Color(red: 1, green: 0.85, blue: 0.72)
            case .day: base = .white
            }
            for i in 0..<count {
                let x0 = Double.random(in: 0...1, using: &rng)
                let y = Double.random(in: 0.02...(0.3 + cover * 0.25), using: &rng) * size.height
                let scale = Double.random(in: 0.7...1.4, using: &rng) * (1 + cover * 0.8) * k
                let speed = Double.random(in: 0.006...0.012, using: &rng) * speedK
                let alpha = (0.12 + cover * 0.45) * Double.random(in: 0.7...1, using: &rng)
                let span = size.width + 260 * scale
                let x = ((x0 * span + time * speed * size.width).truncatingRemainder(dividingBy: span)) - 130 * scale
                var cloud = Path()
                cloud.addEllipse(in: CGRect(x: x, y: y, width: 110 * scale, height: 26 * scale))
                cloud.addEllipse(in: CGRect(x: x + 28 * scale, y: y - 15 * scale, width: 70 * scale, height: 36 * scale))
                cloud.addEllipse(in: CGRect(x: x + 60 * scale, y: y - 6 * scale, width: 62 * scale, height: 28 * scale))
                // Дождевые и грозовые облака серые, грозовые темнее и тяжелее.
                let rainy = atmosphere.precipitation != .none || cover > 0.85
                let shade = max(dark, rainy ? 0.22 : 0)
                let tone = i % 3 == 0 ? shade : shade * 0.8
                let grey = Color(red: 0.85 - tone * 0.62, green: 0.87 - tone * 0.62, blue: 0.9 - tone * 0.58)
                let night = phase == .night ? Color(white: 0.22 - tone * 0.1) : grey
                context.fill(cloud, with: .color((shade > 0.05 ? night : base).opacity(min(0.92, alpha + shade * 0.35))))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Молния: вспышка неба и ломаный разряд. Ритм зависит от силы грозы.
struct LightningLayer: View {
    let atmosphere: Atmosphere
    let time: Double
    let groundY: CGFloat

    /// Яркость вспышки в момент времени и номер разряда.
    static func flash(_ strength: Double, at time: Double) -> (amount: Double, index: Int) {
        guard strength > 0 else { return (0, 0) }
        let period = 9 - strength * 5.5
        let index = Int(floor(time / period))
        let t = time - Double(index) * period
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: index &* 7919 &+ 13))
        let offset = Double.random(in: 0...(period * 0.6), using: &rng)
        let dt = t - offset
        guard dt >= 0, dt < 0.45 else { return (0, index) }
        // Двойная вспышка: короткая, пауза, вторая ярче.
        let first = dt < 0.08 ? 1 - dt / 0.08 : 0
        let second = dt >= 0.14 ? max(0, 1 - (dt - 0.14) / 0.3) : 0
        return (max(first * 0.7, second) * (0.6 + strength * 0.4), index)
    }

    var body: some View {
        Canvas { ctx, size in
            let (amount, index) = Self.flash(atmosphere.lightning, at: time)
            guard amount > 0.01 else { return }
            var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: index &* 104_729 &+ 3))
            var x = size.width * Double.random(in: 0.15...0.85, using: &rng)
            var y = size.height * 0.08
            var bolt = Path()
            bolt.move(to: CGPoint(x: x, y: y))
            let steps = 9
            let stepY = (groundY - y) / CGFloat(steps)
            var branches: [Path] = []
            for i in 0..<steps {
                x += Double.random(in: -18...18, using: &rng) * size.height / 470
                y += stepY
                bolt.addLine(to: CGPoint(x: x, y: y))
                if i == 3 || i == 5, Double.random(in: 0...1, using: &rng) > 0.4 {
                    var branch = Path()
                    branch.move(to: CGPoint(x: x, y: y))
                    branch.addLine(to: CGPoint(x: x + Double.random(in: -40...40, using: &rng), y: y + stepY * 1.6))
                    branches.append(branch)
                }
            }
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(red: 0.8, green: 0.85, blue: 1).opacity(amount), radius: 8))
                layer.stroke(bolt, with: .color(.white.opacity(amount)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                for b in branches { layer.stroke(b, with: .color(.white.opacity(amount * 0.7)), lineWidth: 1.2) }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Дымка, дым или пыль поверх дальнего плана.
struct VeilLayer: View {
    let atmosphere: Atmosphere
    let phase: SkyPhase

    var body: some View {
        let color: Color
        switch atmosphere.veil {
        case .none: color = .clear
        case .haze: color = phase == .night ? Color(white: 0.3) : Color(red: 0.9, green: 0.86, blue: 0.74)
        case .smoke: color = Color(red: 0.45, green: 0.4, blue: 0.36)
        case .dust: color = Color(red: 0.78, green: 0.58, blue: 0.32)
        }
        return LinearGradient(colors: [color.opacity(atmosphere.veilAmount * 0.35), color.opacity(atmosphere.veilAmount * 0.8)],
                              startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }
}

/// Полосы тумана, медленно плывущие над землёй.
struct FogLayer: View {
    let amount: Double
    let phase: SkyPhase
    let time: Double
    /// Ближний туман (перед фигурами) прозрачнее, дальний гуще.
    var near = false

    var body: some View {
        Canvas { ctx, size in
            guard amount > 0.01 else { return }
            let color = phase == .night ? Color(white: 0.42) : Color(white: 0.9)
            if !near {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(amount * 0.45)))
            }
            if near {
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45)),
                         with: .linearGradient(Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: color.opacity(amount * 0.3), location: 0.55),
                            .init(color: color.opacity(amount * 0.18), location: 1)
                         ]), startPoint: CGPoint(x: 0, y: size.height * 0.55), endPoint: CGPoint(x: 0, y: size.height)))
                return
            }
            let bands: [(y: Double, h: Double, speed: Double)] = [(0.58, 0.16, 0.006), (0.68, 0.14, -0.008), (0.74, 0.18, 0.01)]
            for (i, band) in bands.enumerated() {
                let shift = sin(time * band.speed * 6 + Double(i)) * size.width * 0.08
                let rect = CGRect(x: -size.width * 0.2 + shift, y: size.height * band.y, width: size.width * 1.4, height: size.height * band.h)
                ctx.fill(Path(ellipseIn: rect),
                         with: .linearGradient(Gradient(colors: [.clear, color.opacity(amount * 0.55), .clear]),
                                               startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Осадки: дождь, морось, ливень, снег, мокрый снег, ледяной дождь, град.
struct PrecipitationLayer: View {
    let atmosphere: Atmosphere
    let time: Double

    private struct Spec {
        var count: Int
        var length: Double      // длина штриха, 0 — точка
        var speed: Double       // доля высоты в секунду
        var size: ClosedRange<Double>
        var color: Color
        var flake: Bool
    }

    private var specs: [Spec] {
        let rainColor = Color(white: 0.88)
        let iceColor = Color(red: 0.82, green: 0.92, blue: 1)
        switch atmosphere.precipitation {
        case .none: return []
        case .drizzle: return [Spec(count: 110, length: 6, speed: 0.55, size: 0.6...0.9, color: rainColor.opacity(0.35), flake: false)]
        case .lightRain: return [Spec(count: 90, length: 11, speed: 0.85, size: 0.8...1, color: rainColor.opacity(0.45), flake: false)]
        case .rain: return [Spec(count: 170, length: 15, speed: 1.0, size: 0.9...1.1, color: rainColor.opacity(0.5), flake: false)]
        case .heavyRain: return [Spec(count: 280, length: 24, speed: 1.35, size: 1...1.4, color: rainColor.opacity(0.55), flake: false)]
        case .flurries: return [Spec(count: 40, length: 0, speed: 0.06, size: 1...2, color: .white.opacity(0.8), flake: true)]
        case .snow: return [Spec(count: 120, length: 0, speed: 0.09, size: 1...2.4, color: .white.opacity(0.85), flake: true)]
        case .heavySnow: return [Spec(count: 240, length: 0, speed: 0.14, size: 1.2...2.8, color: .white.opacity(0.9), flake: true)]
        case .sleet: return [Spec(count: 100, length: 12, speed: 0.9, size: 0.9...1.1, color: rainColor.opacity(0.45), flake: false),
                             Spec(count: 70, length: 0, speed: 0.2, size: 1...2, color: .white.opacity(0.8), flake: true)]
        case .freezingDrizzle: return [Spec(count: 120, length: 6, speed: 0.55, size: 0.6...0.9, color: iceColor.opacity(0.45), flake: false)]
        case .freezingRain: return [Spec(count: 180, length: 15, speed: 1.0, size: 0.9...1.2, color: iceColor.opacity(0.6), flake: false)]
        case .hail: return [Spec(count: 70, length: 12, speed: 1.0, size: 0.9...1.1, color: rainColor.opacity(0.35), flake: false),
                            Spec(count: 110, length: 0, speed: 1.5, size: 1.6...2.8, color: .white.opacity(0.95), flake: false)]
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let wind = atmosphere.wind
            let k = size.height / 470
            for (layerIndex, spec) in specs.enumerated() {
                var rng = SeededGenerator(seed: UInt64(41 + layerIndex * 17))
                var streaks = Path()
                let count = Int(Double(spec.count) * max(0.45, min(1, k)))
                for _ in 0..<count {
                    let x0 = Double.random(in: 0...1, using: &rng)
                    let y0 = Double.random(in: 0...1, using: &rng)
                    let speed = Double.random(in: 0.75...1.25, using: &rng)
                    let r = Double.random(in: spec.size, using: &rng) * max(0.6, k)
                    let wobble = spec.flake ? sin(time * 1.3 + x0 * 40) * 0.012 : 0
                    let fall = (y0 + time * spec.speed * speed).truncatingRemainder(dividingBy: 1)
                    // Ветер сносит частицы вбок; снег сильнее, чем дождь.
                    let drift = time * wind * (spec.flake ? 0.25 : 0.12) * speed + fall * wind * (spec.flake ? 0.4 : 0.25)
                    let x = ((x0 + drift + wobble).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * size.width
                    let y = fall * size.height
                    if spec.length > 0 {
                        let slant = 0.12 + wind * 0.75
                        let len = spec.length * (0.85 + speed * 0.3) * k
                        streaks.move(to: CGPoint(x: x, y: y))
                        streaks.addLine(to: CGPoint(x: x - len * slant, y: y - len))
                        _ = r
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(spec.color))
                    }
                }
                if spec.length > 0 {
                    ctx.stroke(streaks, with: .color(spec.color), style: StrokeStyle(lineWidth: spec.size.upperBound * max(0.6, k), lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Позёмка: снег или пыль несётся низко над землёй.
struct GroundDriftLayer: View {
    let snow: Double
    let dust: Double
    let wind: Double
    let time: Double

    var body: some View {
        Canvas { ctx, size in
            for (amount, color, seed) in [(snow, Color.white.opacity(0.6), UInt64(91)), (dust, Color(red: 0.86, green: 0.66, blue: 0.38).opacity(0.65), UInt64(93))] where amount > 0.01 {
                var rng = SeededGenerator(seed: seed)
                var path = Path()
                let k = size.height / 470
                for _ in 0..<Int(90 * amount * max(0.5, min(1, k))) {
                    let x0 = Double.random(in: 0...1, using: &rng)
                    let y = Double.random(in: 0.64...0.98, using: &rng) * size.height
                    let speed = Double.random(in: 0.6...1.4, using: &rng) * (0.25 + wind * 0.5)
                    let len = Double.random(in: 10...28, using: &rng) * k
                    let x = ((x0 + time * speed).truncatingRemainder(dividingBy: 1)) * (size.width + 40) - 20
                    let lift = sin(time * 3 + x0 * 30) * 2
                    path.move(to: CGPoint(x: x, y: y + lift))
                    path.addLine(to: CGPoint(x: x - len, y: y + lift + 1.5))
                }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2 * max(0.6, k), lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Струи ветра: тонкие изогнутые линии, бегущие по небу и над степью.
struct WindStreakLayer: View {
    let wind: Double
    let time: Double

    var body: some View {
        Canvas { ctx, size in
            guard wind > 0.4 else { return }
            let k = size.height / 470
            var rng = SeededGenerator(seed: 61)
            let count = Int((wind - 0.3) * 16)
            for _ in 0..<count {
                let x0 = Double.random(in: 0...1, using: &rng)
                let y = Double.random(in: 0.12...0.85, using: &rng) * size.height
                let speed = Double.random(in: 0.25...0.5, using: &rng) * wind
                let len = Double.random(in: 50...110, using: &rng) * k
                let cycle = (x0 + time * speed).truncatingRemainder(dividingBy: 1.4)
                let x = cycle * size.width - len
                // Струя видна только середину своего пролёта.
                let fade = sin(min(1, cycle / 1.2) * .pi)
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addCurve(to: CGPoint(x: x + len, y: y - 4 * k),
                              control1: CGPoint(x: x + len * 0.35, y: y - 7 * k),
                              control2: CGPoint(x: x + len * 0.65, y: y + 5 * k))
                ctx.stroke(path, with: .color(Color.white.opacity(0.28 * fade)), style: StrokeStyle(lineWidth: 1.1 * max(0.7, k), lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Марево над горизонтом в жару.
struct HeatShimmerLayer: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<7 {
                let baseY = size.height * (0.62 + Double(i) * 0.03)
                var wave = Path()
                for step in 0...60 {
                    let x = size.width * Double(step) / 60
                    let y = baseY + sin(x / 18 + time * 4 + Double(i)) * 1.6
                    step == 0 ? wave.move(to: CGPoint(x: x, y: y)) : wave.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(wave, with: .color(Color(red: 1, green: 0.9, blue: 0.7).opacity(0.12)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Искры инея в морозном воздухе.
struct FrostSparkleLayer: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: 77)
            for i in 0..<45 {
                let x = Double.random(in: 0...1, using: &rng) * size.width
                let y = Double.random(in: 0.05...0.95, using: &rng) * size.height
                let twinkle = max(0, sin(time * (1.5 + Double(i % 5) * 0.4) + Double(i)))
                let r = 0.6 + twinkle * 1.2
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(0.25 + twinkle * 0.6)))
            }
        }
        .allowsHitTesting(false)
    }
}
