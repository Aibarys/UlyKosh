import AppKit
import CoreGraphics

// Рисует иконку приложения: чёрный фон, золотой всадник в стиле пиктограмм, тонкая рамка.
// Три варианта: обычная, тёмная (без фона, прозрачная) и тонированная (серая маска).

let size: CGFloat = 1024
let gold = CGColor(red: 0.86, green: 0.66, blue: 0.28, alpha: 1)
let night = CGColor(red: 0.045, green: 0.045, blue: 0.055, alpha: 1)

struct P { let x: CGFloat; let y: CGFloat }

// Контуры всадника из Pictograms.swift (система 100×100, ось Y вниз).
/// Многоугольник с единым направлением обхода, чтобы силуэты складывались, а не вычитались.
func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    var area: CGFloat = 0
    for i in 0..<pts.count {
        let (x1, y1) = pts[i], (x2, y2) = pts[(i + 1) % pts.count]
        area += x1 * y2 - x2 * y1
    }
    let ordered = area < 0 ? Array(pts.reversed()) : pts
    let p = CGMutablePath()
    p.move(to: CGPoint(x: ordered[0].0, y: ordered[0].1))
    for q in ordered.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
    p.closeSubpath()
    return p
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
}
func leg(_ x: CGFloat, _ top: CGFloat, _ bottom: CGFloat, width: CGFloat = 6, lean: CGFloat = 0) -> CGPath {
    poly([(x, top), (x + width, top), (x + width + lean, bottom), (x + lean, bottom)])
}
func bar(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), width: CGFloat) -> CGPath {
    let dx = b.0 - a.0, dy = b.1 - a.1
    let len = max(hypot(dx, dy), 0.001)
    let nx = -dy / len * width / 2, ny = dx / len * width / 2
    return poly([(a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny)])
}

func riderPath() -> CGPath {
    let p = CGMutablePath()
    // лошадь
    p.addPath(poly([(14, 50), (22, 44), (34, 40), (50, 38), (64, 40), (72, 36), (78, 26), (84, 18), (90, 16), (98, 20), (100, 26), (94, 30),
                    (88, 34), (82, 42), (78, 52), (70, 58), (50, 60), (30, 60), (20, 58)]))
    p.addPath(poly([(70, 38), (69, 31), (74, 26), (79, 20), (84, 17), (87, 21), (82, 25), (78, 31), (76, 38)]))
    p.addPath(poly([(85, 18), (87, 11), (90, 17)]))
    p.addPath(poly([(90, 17), (93, 11), (95, 17)]))
    p.addPath(poly([(14, 50), (20, 50), (17, 64), (15, 78), (8, 77), (9, 62)]))
    p.addPath(leg(24, 51, 92, width: 6, lean: -3))
    p.addPath(leg(32, 51, 92, width: 6, lean: 1))
    p.addPath(leg(62, 50, 92, width: 6, lean: -1))
    p.addPath(leg(69, 47, 92, width: 6, lean: 3))
    // всадник
    p.addPath(poly([(45, 42), (58, 42), (56, 20), (47, 20)]))
    p.addPath(ellipse(52, 13, 6, 6))
    p.addPath(poly([(45, 12), (52, 1), (59, 12)]))
    p.addPath(bar((55, 25), (69, 32), width: 4))
    p.addPath(bar((48, 41), (45, 62), width: 4.5))
    p.addPath(poly([(41, 60), (50, 60), (50, 64), (41, 64)]))
    return p
}

func render(variant: String) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CoreGraphics: ось Y вверх, переворачиваем
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let ink: CGColor = variant == "tinted" ? CGColor(gray: 0.85, alpha: 1) : gold

    if variant == "light" {
        ctx.setFillColor(night)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // едва заметная виньетка к центру
        let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1), night] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: size / 2, y: size * 0.55), startRadius: 0, endCenter: CGPoint(x: size / 2, y: size * 0.55), endRadius: size * 0.7, options: [])
    }

    // рамка: двойная линия с отступом, как на карте
    let outer = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.075, dy: size * 0.075)
    let inner = outer.insetBy(dx: size * 0.018, dy: size * 0.018)
    ctx.setStrokeColor(ink.copy(alpha: 0.9)!)
    ctx.setLineWidth(size * 0.010)
    ctx.stroke(outer)
    ctx.setStrokeColor(ink.copy(alpha: 0.45)!)
    ctx.setLineWidth(size * 0.005)
    ctx.stroke(inner)

    // всадник: система 100×100 в квадрат 62% иконки, смотрит вправо
    let scale = size * 0.62 / 100
    ctx.saveGState()
    ctx.translateBy(x: (size - 100 * scale) / 2, y: (size - 100 * scale) / 2 + size * 0.02)
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(ink)
    ctx.addPath(riderPath())
    ctx.fillPath(using: .winding)
    ctx.restoreGState()

    // линия земли под копытами
    ctx.setStrokeColor(ink.copy(alpha: 0.7)!)
    ctx.setLineWidth(size * 0.008)
    ctx.setLineCap(.round)
    let groundY = (size - 100 * scale) / 2 + size * 0.02 + 92 * scale + size * 0.012
    ctx.move(to: CGPoint(x: size * 0.22, y: groundY))
    ctx.addLine(to: CGPoint(x: size * 0.78, y: groundY))
    ctx.strokePath()

    return ctx.makeImage()!
}

let outDir = CommandLine.arguments.dropFirst().first ?? "."
for variant in ["light", "dark", "tinted"] {
    let img = render(variant: variant)
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon-\(variant).png")
    try! data.write(to: url)
    print("wrote", url.path)
}
