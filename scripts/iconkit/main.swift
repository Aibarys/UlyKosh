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
    // Путник с котомкой и посохом, тот же контур, что .walker в Pictograms.swift.
    let p = CGMutablePath()
    p.addPath(ellipse(56, 13, 6.5, 6.5))
    p.addPath(poly([(48, 11), (56, 1), (64, 11)]))
    p.addPath(poly([(49, 22), (62, 22), (61, 55), (50, 55)]))
    p.addPath(poly([(39, 25), (50, 24), (50, 47), (40, 47)]))
    p.addPath(bar((52, 53), (39, 93), width: 6.5))
    p.addPath(poly([(33, 91), (43, 91), (43, 96), (31, 96)]))
    p.addPath(bar((58, 53), (64, 73), width: 6.5))
    p.addPath(bar((64, 73), (70, 93), width: 6))
    p.addPath(poly([(67, 91), (78, 91), (78, 96), (67, 96)]))
    p.addPath(bar((59, 26), (73, 41), width: 4.5))
    p.addPath(bar((76, 12), (79, 96), width: 3.5))
    return p
}

func render(variant: String) -> CGImage {
    if variant == "launch" { return renderLaunch() }
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

    // всадник: система 100×100 в квадрат 62% иконки, смотрит вправо
    let scale = size * 0.66 / 100
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
    let groundY = (size - 100 * scale) / 2 + size * 0.02 + 96 * scale + size * 0.006
    ctx.move(to: CGPoint(x: size * 0.22, y: groundY))
    ctx.addLine(to: CGPoint(x: size * 0.78, y: groundY))
    ctx.strokePath()

    return ctx.makeImage()!
}

/// Экран запуска: чёрный фон, небольшой всадник и линия земли, центр чуть выше середины.
func renderLaunch() -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let side: CGFloat = 1024
    let ctx = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: side)
    ctx.scaleBy(x: 1, y: -1)
    // прозрачный фон: цвет фона задаёт сам экран запуска
    let scale = side * 0.34 / 100
    ctx.saveGState()
    ctx.translateBy(x: (side - 100 * scale) / 2, y: (side - 100 * scale) / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(gold)
    ctx.addPath(riderPath())
    ctx.fillPath(using: .winding)
    ctx.restoreGState()
    ctx.setStrokeColor(gold.copy(alpha: 0.7)!)
    ctx.setLineWidth(side * 0.004)
    ctx.setLineCap(.round)
    let groundY = (side - 100 * scale) / 2 + 96 * scale + side * 0.004
    ctx.move(to: CGPoint(x: side * 0.34, y: groundY))
    ctx.addLine(to: CGPoint(x: side * 0.66, y: groundY))
    ctx.strokePath()
    return ctx.makeImage()!
}

let outDir = CommandLine.arguments.dropFirst().first ?? "."
for variant in ["light", "dark", "tinted", "launch"] {
    let img = render(variant: variant)
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    let name = variant == "launch" ? "LaunchRider.png" : "AppIcon-\(variant).png"
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! data.write(to: url)
    print("wrote", url.path)
}
