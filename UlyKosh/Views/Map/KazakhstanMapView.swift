import SwiftUI

struct MapCamera: Equatable {
    var center: CGPoint
    var zoom: Double
}

private struct CameraAnimation {
    let id = UUID()
    let from: MapCamera
    let to: MapCamera
    let start: Date
    let duration: TimeInterval

    func camera(at date: Date) -> MapCamera {
        let raw = max(0, min(1, date.timeIntervalSince(start) / duration))
        let t = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        return MapCamera(
            center: CGPoint(x: from.center.x + (to.center.x - from.center.x) * t, y: from.center.y + (to.center.y - from.center.y) * t),
            zoom: from.zoom + (to.zoom - from.zoom) * t
        )
    }
}

/// Интерактивная карта Казахстана в стиле старинной гравюры с маршрутом кочевья.
struct KazakhstanMapView: View {
    @Environment(GameEngine.self) private var engine
    let world: MapWorld

    @State private var camera: MapCamera
    @State private var animation: CameraAnimation?
    @State private var dragBase: (center: CGPoint, translation: CGSize)?
    @State private var zoomBase: (camera: MapCamera, anchorWorld: CGPoint, anchorScreen: CGPoint)?
    @State private var revealStart: Date?
    @State private var revealFinished = false
    @State private var introStarted = false

    private let route: RouteGeometry
    private let revealDuration: TimeInterval = 2.2
    private let minZoom = 1.0
    private let maxZoom = 9.0

    /// Силуэты-виньетки: эмодзи и координаты.
    private let vignettes: [(icon: Pictogram, point: GeoPoint)] = [
        (.saiga, GeoPoint(lat: 46.0, lon: 70.6)),
        (.camel, GeoPoint(lat: 44.35, lon: 64.6)),
        (.mausoleum, GeoPoint(lat: 42.95, lon: 67.55)),
        (.horse, GeoPoint(lat: 49.4, lon: 71.6)),
        (.ram, GeoPoint(lat: 48.9, lon: 66.6)),
        (.eagle, GeoPoint(lat: 49.4, lon: 85.4)),
        (.yurt, GeoPoint(lat: 50.9, lon: 61.2)),
        (.wolf, GeoPoint(lat: 47.3, lon: 76.6)),
        (.tulip, GeoPoint(lat: 44.2, lon: 67.2)),
        (.deer, GeoPoint(lat: 44.6, lon: 76.0)),
        (.boar, GeoPoint(lat: 48.6, lon: 55.4))
    ]

    init(world: MapWorld, stops: [Stop]) {
        self.world = world
        route = RouteGeometry(points: stops.map { world.projection.project($0.coordinate) }, kms: stops.map(\.km))
        _camera = State(initialValue: MapCamera(center: CGPoint(x: world.bounds.midX, y: world.bounds.midY), zoom: 1))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: animation == nil && revealFinished)) { timeline in
                let now = timeline.date
                let cam = displayedCamera(at: now)
                let s = screenScale(zoom: cam.zoom, size: size)
                let transform = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: size.width / 2 - cam.center.x * s, ty: size.height / 2 - cam.center.y * s)
                let reveal = revealProgress(at: now)
                let travelled = route.fraction(atKm: engine.totalKm)

                ZStack {
                    MapCanvas(
                        world: world,
                        route: route,
                        transform: transform,
                        zoom: cam.zoom,
                        viewport: CGRect(origin: .zero, size: size),
                        travelled: travelled * reveal
                    )
                    overlays(transform: transform, zoom: cam.zoom, reveal: reveal, travelled: travelled)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: size))
            .simultaneousGesture(magnifyGesture(size: size))
            .simultaneousGesture(doubleTap(size: size))
            .overlay(alignment: .bottomLeading) { scaleBar(size: size).padding(.leading, 68).padding(.bottom, 24) }
            .overlay(alignment: .bottomTrailing) { controls(size: size).padding(.trailing, 20).padding(.bottom, 72) }
            .overlay(alignment: .topTrailing) { CompassRose().padding(.top, 118).padding(.trailing, 20) }
            .overlay { MapFrame().allowsHitTesting(false) }
            .onAppear { startIntro(size: size) }
        }
        .background(Color.night)
        .clipped()
    }

    // MARK: - Оверлеи

    @ViewBuilder
    private func overlays(transform: CGAffineTransform, zoom: Double, reveal: Double, travelled: Double) -> some View {
        let stops = engine.route.stops
        let showLabels = zoom >= 2.0

        if zoom >= 1.6 {
            ForEach(Array(vignettes.enumerated()), id: \.offset) { _, v in
                PictogramView(kind: v.icon, size: min(12 + zoom * 2, 28), tint: Color.ash.opacity(0.8))
                    .position(world.projection.project(v.point).applying(transform))
                    .allowsHitTesting(false)
            }
        }

        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
            let point = world.projection.project(stop.coordinate).applying(transform)
            let reached = stop.km <= engine.totalKm
            let isCurrent = stop.id == engine.currentStop.id && !engine.isFinished
            let appear = reveal >= route.fraction(atKm: stop.km) - 0.01 || !reached
            let marker = StopMarker(stop: stop, reached: reached, isCurrent: isCurrent, showLabel: showLabels || (isCurrent && zoom >= 1.5), labelOnLeft: index % 2 == 1)

            Group {
                if reached {
                    NavigationLink(value: stop) { marker }.buttonStyle(.plain)
                } else {
                    marker
                }
            }
            .position(point)
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.5)
            .animation(.spring(duration: 0.45, bounce: 0.3), value: appear)
        }

        CaravanMarker()
            .position(route.point(atFraction: travelled * reveal).applying(transform))
    }

    // MARK: - Камера

    private func screenScale(zoom: Double, size: CGSize) -> CGFloat {
        let base = min(size.width / world.bounds.width, size.height / world.bounds.height) * 0.9
        return base * zoom
    }

    private func displayedCamera(at date: Date) -> MapCamera {
        animation?.camera(at: date) ?? camera
    }

    private func revealProgress(at date: Date) -> Double {
        guard let start = revealStart else { return 0 }
        let raw = max(0, min(1, date.timeIntervalSince(start) / revealDuration))
        return raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
    }

    private func clamped(center: CGPoint, zoom: Double, size: CGSize) -> CGPoint {
        let s = screenScale(zoom: zoom, size: size)
        let halfW = size.width / 2 / s, halfH = size.height / 2 / s
        let b = world.bounds.insetBy(dx: -world.bounds.width * 0.08, dy: -world.bounds.height * 0.08)
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi) }
        return CGPoint(x: clamp(center.x, b.minX + halfW * 0.5, b.maxX - halfW * 0.5),
                       y: clamp(center.y, b.minY + halfH * 0.5, b.maxY - halfH * 0.5))
    }

    private func animateCamera(to target: MapCamera, duration: TimeInterval) {
        let from = displayedCamera(at: .now)
        let anim = CameraAnimation(from: from, to: target, start: .now, duration: duration)
        animation = anim
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if animation?.id == anim.id {
                camera = target
                animation = nil
            }
        }
    }

    private func settleAnimation() {
        if let anim = animation {
            camera = anim.camera(at: .now)
            animation = nil
        }
    }

    private var caravanWorld: CGPoint { route.point(atFraction: route.fraction(atKm: engine.totalKm)) }

    private func startIntro(size: CGSize) {
        guard !introStarted else { return }
        introStarted = true
        let target = MapCamera(center: clamped(center: caravanWorld, zoom: 3.4, size: size), zoom: 3.4)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            revealStart = .now
            animateCamera(to: target, duration: 1.9)
            try? await Task.sleep(for: .seconds(revealDuration + 0.1))
            revealFinished = true
        }
    }

    // MARK: - Жесты

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if zoomBase != nil { dragBase = nil; return }
                settleAnimation()
                if dragBase == nil { dragBase = (camera.center, value.translation) }
                guard let base = dragBase else { return }
                let s = screenScale(zoom: camera.zoom, size: size)
                let dx = (value.translation.width - base.translation.width) / s
                let dy = (value.translation.height - base.translation.height) / s
                camera.center = clamped(center: CGPoint(x: base.center.x - dx, y: base.center.y - dy), zoom: camera.zoom, size: size)
            }
            .onEnded { _ in dragBase = nil }
    }

    private func magnifyGesture(size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                settleAnimation()
                if zoomBase == nil {
                    let anchorScreen = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                    let s = screenScale(zoom: camera.zoom, size: size)
                    let anchorWorld = CGPoint(x: camera.center.x + (anchorScreen.x - size.width / 2) / s,
                                              y: camera.center.y + (anchorScreen.y - size.height / 2) / s)
                    zoomBase = (camera, anchorWorld, anchorScreen)
                }
                guard let base = zoomBase else { return }
                let zoom = max(minZoom, min(maxZoom, base.camera.zoom * value.magnification))
                let s = screenScale(zoom: zoom, size: size)
                let center = CGPoint(x: base.anchorWorld.x - (base.anchorScreen.x - size.width / 2) / s,
                                     y: base.anchorWorld.y - (base.anchorScreen.y - size.height / 2) / s)
                camera = MapCamera(center: clamped(center: center, zoom: zoom, size: size), zoom: zoom)
            }
            .onEnded { _ in
                zoomBase = nil
                dragBase = nil
            }
    }

    private func doubleTap(size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let cam = displayedCamera(at: .now)
                let s = screenScale(zoom: cam.zoom, size: size)
                let worldPoint = CGPoint(x: cam.center.x + (value.location.x - size.width / 2) / s,
                                         y: cam.center.y + (value.location.y - size.height / 2) / s)
                let zoom = cam.zoom >= maxZoom * 0.8 ? 1 : min(maxZoom, cam.zoom * 2)
                animateCamera(to: MapCamera(center: clamped(center: worldPoint, zoom: zoom, size: size), zoom: zoom), duration: 0.5)
            }
    }

    // MARK: - Элементы управления

    private func controls(size: CGSize) -> some View {
        VStack(spacing: 10) {
            mapButton("location.north.line") {
                let zoom = max(displayedCamera(at: .now).zoom, 3.4)
                animateCamera(to: MapCamera(center: clamped(center: caravanWorld, zoom: zoom, size: size), zoom: zoom), duration: 0.9)
            }
            mapButton("arrow.down.right.and.arrow.up.left") {
                animateCamera(to: MapCamera(center: CGPoint(x: world.bounds.midX, y: world.bounds.midY), zoom: 1), duration: 0.9)
            }
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.gold)
                .frame(width: 40, height: 40)
                .background(Color.night.opacity(0.85), in: Circle())
                .overlay(Circle().stroke(Color.gold.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }

    private func scaleBar(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: animation == nil)) { timeline in
            let zoom = displayedCamera(at: timeline.date).zoom
            let kmPerPoint = world.kmPerUnit / Double(screenScale(zoom: zoom, size: size))
            let options: [Double] = [10, 25, 50, 100, 200, 500, 1000]
            let km = options.last(where: { $0 / kmPerPoint <= 120 }) ?? 10
            let width = km / kmPerPoint
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Int(km)) км")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(Color.ash)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gold.opacity(0.7)).frame(width: width, height: 1)
                    Rectangle().fill(Color.gold.opacity(0.7)).frame(width: 1, height: 6)
                    Rectangle().fill(Color.gold.opacity(0.7)).frame(width: 1, height: 6).offset(x: width - 1)
                }
            }
        }
    }
}

// MARK: - Отрисовка карты

private struct MapCanvas: View {
    let world: MapWorld
    let route: RouteGeometry
    let transform: CGAffineTransform
    let zoom: Double
    let viewport: CGRect
    let travelled: Double

    private var waterFill: Color { Color(red: 0.06, green: 0.14, blue: 0.20) }
    private var waterLine: Color { Color(red: 0.38, green: 0.60, blue: 0.72) }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let visible = viewport.insetBy(dx: -40, dy: -40)
            let s = transform.a
            func onScreen(_ p: CGPoint) -> Bool { visible.contains(p) }

            // Территория
            let border = world.border.applying(transform)
            ctx.fill(border, with: .color(Color.gold.opacity(0.035)))

            // Вода: заливка, штриховка и контур
            for water in world.waters {
                let wb = water.bounds.applying(transform)
                guard wb.intersects(visible) else { continue }
                let path = water.path.applying(transform)
                ctx.fill(path, with: .color(waterFill))
                if wb.height > 14 {
                    ctx.drawLayer { layer in
                        layer.clip(to: path)
                        var lines = Path()
                        let step: CGFloat = 5
                        var y = wb.minY + step
                        while y < wb.maxY {
                            lines.move(to: CGPoint(x: max(wb.minX, visible.minX), y: y))
                            lines.addLine(to: CGPoint(x: min(wb.maxX, visible.maxX), y: y))
                            y += step
                        }
                        layer.stroke(lines, with: .color(waterLine.opacity(0.28)), lineWidth: 0.6)
                    }
                }
                ctx.stroke(path, with: .color(waterLine.opacity(0.85)), lineWidth: 1)
            }

            // Рельеф
            let glyph = CGFloat(min(max(4.6 * pow(zoom, 0.35), 4.5), 8))
            var ranges = Path(), hills = Path(), plateau = Path(), deserts = Path()
            for group in world.symbols {
                for wp in group.points {
                    let p = wp.applying(transform)
                    guard onScreen(p) else { continue }
                    switch group.kind {
                    case .range:
                        ranges.move(to: CGPoint(x: p.x - glyph, y: p.y))
                        ranges.addLine(to: CGPoint(x: p.x, y: p.y - glyph * 1.15))
                        ranges.addLine(to: CGPoint(x: p.x + glyph, y: p.y))
                        ranges.move(to: CGPoint(x: p.x, y: p.y - glyph * 1.15))
                        ranges.addLine(to: CGPoint(x: p.x + glyph * 0.38, y: p.y - glyph * 0.4))
                    case .hills:
                        let g = glyph * 0.55
                        hills.move(to: CGPoint(x: p.x - g, y: p.y))
                        hills.addQuadCurve(to: CGPoint(x: p.x + g, y: p.y), control: CGPoint(x: p.x, y: p.y - g * 1.4))
                    case .plateau:
                        let g = glyph * 0.7
                        plateau.move(to: CGPoint(x: p.x - g, y: p.y))
                        plateau.addLine(to: CGPoint(x: p.x + g, y: p.y))
                        plateau.move(to: CGPoint(x: p.x - g * 0.5, y: p.y + 2.5))
                        plateau.addLine(to: CGPoint(x: p.x + g * 0.5, y: p.y + 2.5))
                    case .desert:
                        let r: CGFloat = 0.9
                        deserts.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    }
                }
            }
            ctx.fill(deserts, with: .color(Color.gold.opacity(0.26)))
            ctx.stroke(hills, with: .color(Color.gold.opacity(0.30)), lineWidth: 0.7)
            ctx.stroke(plateau, with: .color(Color.gold.opacity(0.28)), lineWidth: 0.7)
            ctx.stroke(ranges, with: .color(Color.gold.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))

            // Реки
            for river in world.rivers {
                let path = river.path.applying(transform)
                guard path.boundingRect.intersects(visible) else { continue }
                let width = CGFloat(0.5 + river.width * 0.35) * CGFloat(min(1 + (zoom - 1) * 0.12, 1.6))
                ctx.stroke(path, with: .color(waterLine.opacity(0.9)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            // Граница страны со свечением
            ctx.stroke(border, with: .color(Color.gold.opacity(0.12)), lineWidth: 7)
            ctx.stroke(border, with: .color(Color.gold.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

            // Маршрут
            let routePath = route.path.applying(transform)
            ctx.stroke(routePath, with: .color(Color.gold.opacity(0.35)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 5]))
            if travelled > 0 {
                let done = routePath.trimmedPath(from: 0, to: travelled)
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: Color.gold.opacity(0.6), radius: 5))
                    layer.stroke(done, with: .color(Color.gold), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
            }

            // Подписи природы: на общем виде только крупные объекты
            let majorLabels: Set<String> = ["Сарыарқа", "Бетпақдала", "Қызылқұм", "Үстірт", "Алтай", "Тянь-Шань", "Каспий теңізі", "Арал теңізі", "Балқаш", "Қаратау", "Ұлытау"]
            for label in world.labels {
                let p = label.at.applying(transform)
                guard onScreen(p) else { continue }
                if label.kind == "plain" && zoom < 1.4 { continue }
                if zoom < 1.7 && !majorLabels.contains(label.text) { continue }
                let color: Color
                let font: Font
                switch label.kind {
                case "range": color = Color.gold.opacity(0.8); font = .system(size: 11, design: .serif).italic()
                case "desert": color = Color.parchment.opacity(0.6); font = .system(size: 11, design: .serif).italic()
                case "hills", "plateau": color = Color.ash; font = .system(size: 12, design: .serif).italic()
                default: color = Color.ash.opacity(0.85); font = .system(size: 10.5, design: .serif).italic()
                }
                drawText(ctx, label.text, at: p, angle: label.angle, font: font, color: color)
            }
            for water in world.waters {
                guard let name = water.name, let at = water.label else { continue }
                if zoom < 1.7 && !majorLabels.contains(name) { continue }
                let p = at.applying(transform)
                guard onScreen(p) else { continue }
                drawText(ctx, name, at: p, angle: 0, font: .system(size: 11, design: .serif).italic(), color: waterLine.opacity(0.95))
            }
            if zoom >= 1.35 {
                for river in world.rivers {
                    guard let name = river.name, let at = river.label else { continue }
                    let p = at.applying(transform)
                    guard onScreen(p) else { continue }
                    drawText(ctx, name, at: CGPoint(x: p.x, y: p.y - 7), angle: 0, font: .system(size: 9.5, design: .serif).italic(), color: waterLine.opacity(0.9))
                }
            }

            // Города
            for city in world.cities {
                let threshold = city.rank == 1 ? 1.0 : (city.rank == 2 ? 1.6 : 2.6)
                guard zoom >= threshold else { continue }
                let p = city.at.applying(transform)
                guard onScreen(p) else { continue }
                if city.capital {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Color.gold.opacity(0.8)), lineWidth: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Color.gold))
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)), with: .color(Color.ash))
                }
                let text = ctx.resolve(Text(city.name).font(.system(size: city.rank == 1 ? 11 : 10)).foregroundColor(city.capital ? Color.parchment : Color.ash))
                ctx.draw(text, at: CGPoint(x: p.x + 7, y: p.y), anchor: .leading)
            }

            // Исторические места
            if zoom >= 2.6 {
                for place in world.historic {
                    let p = place.at.applying(transform)
                    guard onScreen(p) else { continue }
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: p.x, y: p.y - 4))
                    diamond.addLine(to: CGPoint(x: p.x + 4, y: p.y))
                    diamond.addLine(to: CGPoint(x: p.x, y: p.y + 4))
                    diamond.addLine(to: CGPoint(x: p.x - 4, y: p.y))
                    diamond.closeSubpath()
                    ctx.stroke(diamond, with: .color(Color.gold.opacity(0.75)), lineWidth: 1)
                    let text = ctx.resolve(Text(place.name).font(.system(size: 9.5, design: .serif).italic()).foregroundColor(Color.gold.opacity(0.75)))
                    ctx.draw(text, at: CGPoint(x: p.x + 7, y: p.y), anchor: .leading)
                }
            }
            _ = s
        }
    }

    private func drawText(_ ctx: GraphicsContext, _ text: String, at p: CGPoint, angle: Double, font: Font, color: Color) {
        let resolved = ctx.resolve(Text(text).font(font).foregroundColor(color))
        if angle == 0 {
            ctx.draw(resolved, at: p)
        } else {
            ctx.drawLayer { layer in
                layer.translateBy(x: p.x, y: p.y)
                layer.rotate(by: .degrees(angle))
                layer.draw(resolved, at: .zero)
            }
        }
    }
}

// MARK: - Рамка, роза ветров

/// Орнаментальная рамка: двойная линия и «қошқар мүйіз» в углах.
struct MapFrame: View {
    var body: some View {
        Canvas { ctx, size in
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            let inner = outer.insetBy(dx: 5, dy: 5)
            ctx.stroke(Path(roundedRect: outer, cornerRadius: 3), with: .color(Color.gold.opacity(0.7)), lineWidth: 1.2)
            ctx.stroke(Path(roundedRect: inner, cornerRadius: 2), with: .color(Color.gold.opacity(0.35)), lineWidth: 0.6)

            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: inner.minX, y: inner.minY), 1, 1),
                (CGPoint(x: inner.maxX, y: inner.minY), -1, 1),
                (CGPoint(x: inner.minX, y: inner.maxY), 1, -1),
                (CGPoint(x: inner.maxX, y: inner.maxY), -1, -1)
            ]
            for (corner, sx, sy) in corners {
                ctx.drawLayer { layer in
                    layer.translateBy(x: corner.x, y: corner.y)
                    layer.scaleBy(x: sx, y: sy)
                    layer.stroke(hornOrnament(), with: .color(Color.gold.opacity(0.75)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
            }
        }
    }

    /// Пара завитков бараньих рогов, растущих из угла.
    private func hornOrnament() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 26, y: 26))
        p.addCurve(to: CGPoint(x: 42, y: 22), control1: CGPoint(x: 32, y: 32), control2: CGPoint(x: 44, y: 32))
        p.addCurve(to: CGPoint(x: 33, y: 22), control1: CGPoint(x: 40, y: 15), control2: CGPoint(x: 31, y: 16))
        p.move(to: CGPoint(x: 26, y: 26))
        p.addCurve(to: CGPoint(x: 22, y: 42), control1: CGPoint(x: 32, y: 32), control2: CGPoint(x: 32, y: 44))
        p.addCurve(to: CGPoint(x: 22, y: 33), control1: CGPoint(x: 15, y: 40), control2: CGPoint(x: 16, y: 31))
        p.move(to: CGPoint(x: 6, y: 0))
        p.addLine(to: CGPoint(x: 18, y: 12))
        p.move(to: CGPoint(x: 0, y: 6))
        p.addLine(to: CGPoint(x: 12, y: 18))
        return p
    }
}

struct CompassRose: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
            let long: CGFloat = 18, short: CGFloat = 5
            let pts = [
                CGPoint(x: c.x, y: c.y - long), CGPoint(x: c.x + short, y: c.y - short),
                CGPoint(x: c.x + long, y: c.y), CGPoint(x: c.x + short, y: c.y + short),
                CGPoint(x: c.x, y: c.y + long), CGPoint(x: c.x - short, y: c.y + short),
                CGPoint(x: c.x - long, y: c.y), CGPoint(x: c.x - short, y: c.y - short)
            ]
            var star = Path()
            star.move(to: pts[0])
            for p in pts.dropFirst() { star.addLine(to: p) }
            star.closeSubpath()
            ctx.stroke(star, with: .color(Color.gold.opacity(0.75)), lineWidth: 1)
            var north = Path()
            north.move(to: pts[0]); north.addLine(to: pts[1]); north.addLine(to: c); north.closeSubpath()
            ctx.fill(north, with: .color(Color.gold.opacity(0.8)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(Color.gold.opacity(0.75)), lineWidth: 0.8)
            let n = ctx.resolve(Text("С").font(.system(size: 10, design: .serif)).foregroundColor(Color.gold.opacity(0.85)))
            ctx.draw(n, at: CGPoint(x: c.x, y: c.y - long - 7))
        }
        .frame(width: 44, height: 56)
        .allowsHitTesting(false)
    }
}
