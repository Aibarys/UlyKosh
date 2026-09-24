import SwiftUI

/// Плавная кривая через точки и пересчёт километров в точку на ней.
struct RouteGeometry {
    let path: Path
    private let samples: [(point: CGPoint, km: Double, length: Double)]
    let totalLength: Double

    init(points: [CGPoint], kms: [Double]) {
        var path = Path()
        var samples: [(CGPoint, Double, Double)] = []
        var cumulative = 0.0

        guard let first = points.first, points.count == kms.count else {
            self.path = path
            self.samples = []
            self.totalLength = 0
            return
        }
        path.move(to: first)
        samples.append((first, kms[0], 0))

        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)

            var previous = p1
            var segmentPoints: [(CGPoint, Double)] = []
            var segmentLength = 0.0
            for k in 1...48 {
                let t = Double(k) / 48
                let q = Self.bezier(p1, c1, c2, p2, t)
                segmentLength += hypot(q.x - previous.x, q.y - previous.y)
                previous = q
                segmentPoints.append((q, segmentLength))
            }
            let km0 = kms[i], km1 = kms[i + 1]
            for (q, len) in segmentPoints {
                let f = segmentLength > 0 ? len / segmentLength : 1
                samples.append((q, km0 + (km1 - km0) * f, cumulative + len))
            }
            cumulative += segmentLength
        }

        self.path = path
        self.samples = samples.map { (point: $0.0, km: $0.1, length: $0.2) }
        self.totalLength = cumulative
    }

    func point(atFraction fraction: Double) -> CGPoint {
        guard let first = samples.first, let last = samples.last else { return .zero }
        let target = max(0, min(1, fraction)) * totalLength
        if target <= 0 { return first.point }
        for i in 1..<samples.count where target <= samples[i].length {
            let a = samples[i - 1], b = samples[i]
            let f = b.length > a.length ? (target - a.length) / (b.length - a.length) : 0
            return CGPoint(x: a.point.x + (b.point.x - a.point.x) * f, y: a.point.y + (b.point.y - a.point.y) * f)
        }
        return last.point
    }

    /// Доля длины кривой, пройденная к данному километру.
    func fraction(atKm km: Double) -> Double {
        guard totalLength > 0, let first = samples.first, let last = samples.last else { return 0 }
        if km <= first.km { return 0 }
        if km >= last.km { return 1 }
        for i in 1..<samples.count where km <= samples[i].km {
            let a = samples[i - 1], b = samples[i]
            let f = b.km > a.km ? (km - a.km) / (b.km - a.km) : 0
            return (a.length + (b.length - a.length) * f) / totalLength
        }
        return 1
    }

    private static func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
        let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
        return CGPoint(x: x, y: y)
    }
}

struct CaravanMarker: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(Color.gold.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .blur(radius: 8)
                PictogramView(kind: .camel, size: 24, tint: .gold)
                    .offset(y: CGFloat(sin(t * 5)) * 1.2)
                    .rotationEffect(.degrees(sin(t * 2.5) * 2))
            }
        }
        .allowsHitTesting(false)
    }
}

struct StopMarker: View {
    let stop: Stop
    let reached: Bool
    let isCurrent: Bool
    var showLabel = true
    var labelOnLeft = false

    var body: some View {
        ZStack {
            if isCurrent {
                PulsingDot()
            } else {
                Circle()
                    .stroke(reached ? Color.gold : Color.ash.opacity(0.7), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(Color.night))
                if reached {
                    Circle().fill(Color.gold).frame(width: 6, height: 6)
                }
            }
        }
        .frame(width: 12, height: 12)
        .overlay(alignment: labelOnLeft ? .trailing : .leading) {
            if showLabel {
                label.offset(x: labelOnLeft ? -18 : 18)
            }
        }
        .contentShape(Rectangle().inset(by: -8))
    }

    private var label: some View {
        Text(stop.name)
            .font(.display(12, weight: .regular))
            .foregroundStyle(reached ? Color.parchment : Color.ash)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.night.opacity(0.78), in: Capsule())
    }
}
