import SwiftUI

/// Пиктограммы в духе петроглифов Тамғалы. Рисуются в квадрате 100×100, ось Y вниз, животные смотрят вправо.
enum Pictogram: String, Codable, CaseIterable {
    case camel, horse, sheep, ram, saiga, gazelle, deer, wolf, boar, dog
    case eagle, crane, bird, tortoise, hedgehog, marmot
    case yurt, tree, spruce, reeds, mausoleum, ruins, tulip
    case elder, dombra, well, hammer, crescent
    case snow, whirlwind, wave

    var isStroke: Bool { [.snow, .whirlwind, .wave].contains(self) }
    var evenOdd: Bool { [.yurt, .mausoleum, .crescent].contains(self) }

    var title: String {
        switch self {
        case .camel: return "Верблюд"
        case .horse: return "Лошадь"
        case .sheep: return "Овца"
        case .ram: return "Архар"
        case .saiga: return "Сайгак"
        case .gazelle: return "Джейран"
        case .deer: return "Олень"
        case .wolf: return "Волк"
        case .boar: return "Кабан"
        case .dog: return "Тобет"
        case .eagle: return "Орёл"
        case .crane: return "Журавль"
        case .bird: return "Птица"
        case .tortoise: return "Черепаха"
        case .hedgehog: return "Ёж"
        case .marmot: return "Сурок"
        case .yurt: return "Юрта"
        case .tree: return "Дерево"
        case .spruce: return "Ель"
        case .reeds: return "Камыш"
        case .mausoleum: return "Мавзолей"
        case .ruins: return "Руины"
        case .tulip: return "Тюльпан"
        case .elder: return "Аксакал"
        case .dombra: return "Домбра"
        case .well: return "Колодец"
        case .hammer: return "Молот"
        case .crescent: return "Полумесяц"
        case .snow: return "Снег"
        case .whirlwind: return "Вихрь"
        case .wave: return "Волна"
        }
    }
}

/// Готовый вид пиктограммы нужного размера и цвета.
struct PictogramView: View {
    let kind: Pictogram
    var size: CGFloat = 24
    var tint: Color = .gold

    var body: some View {
        Group {
            if kind.isStroke {
                PictogramShape(kind: kind)
                    .stroke(tint, style: StrokeStyle(lineWidth: max(1, size * 0.055), lineCap: .round, lineJoin: .round))
            } else {
                PictogramShape(kind: kind)
                    .fill(tint, style: FillStyle(eoFill: kind.evenOdd))
            }
        }
        .frame(width: size, height: size)
    }
}

struct PictogramShape: Shape {
    let kind: Pictogram

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let transform = CGAffineTransform(translationX: rect.midX - 50 * s, y: rect.midY - 50 * s).scaledBy(x: s, y: s)
        return PictogramLibrary.path(for: kind).applying(transform)
    }
}

// MARK: - Построение контуров

private struct PathBuilder {
    var path = Path()

    /// Многоугольник с нормализованным направлением обхода, чтобы силуэты складывались, а не вычитались.
    mutating func poly(_ pts: [(CGFloat, CGFloat)], hole: Bool = false) {
        guard pts.count > 2 else { return }
        var area: CGFloat = 0
        for i in 0..<pts.count {
            let (x1, y1) = pts[i], (x2, y2) = pts[(i + 1) % pts.count]
            area += x1 * y2 - x2 * y1
        }
        var ordered = area < 0 ? Array(pts.reversed()) : pts
        if hole { ordered.reverse() }
        path.move(to: CGPoint(x: ordered[0].0, y: ordered[0].1))
        for p in ordered.dropFirst() { path.addLine(to: CGPoint(x: p.0, y: p.1)) }
        path.closeSubpath()
    }

    mutating func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, hole: Bool = false) {
        var pts: [(CGFloat, CGFloat)] = []
        for i in 0..<36 {
            let a = CGFloat(i) / 36 * 2 * .pi
            pts.append((cx + cos(a) * rx, cy + sin(a) * ry))
        }
        poly(pts, hole: hole)
    }

    mutating func leg(_ x: CGFloat, _ top: CGFloat, _ bottom: CGFloat, width: CGFloat = 6, lean: CGFloat = 0) {
        poly([(x, top), (x + width, top), (x + width + lean, bottom), (x + lean, bottom)])
    }

    mutating func bar(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), width: CGFloat) {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let len = max(hypot(dx, dy), 0.001)
        let nx = -dy / len * width / 2, ny = dx / len * width / 2
        poly([(a.0 + nx, a.1 + ny), (b.0 + nx, b.1 + ny), (b.0 - nx, b.1 - ny), (a.0 - nx, a.1 - ny)])
    }

    // Для штриховых иконок
    mutating func stroke(_ pts: [(CGFloat, CGFloat)]) {
        guard let f = pts.first else { return }
        path.move(to: CGPoint(x: f.0, y: f.1))
        for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.0, y: p.1)) }
    }
}

private enum PictogramLibrary {
    static var cache: [Pictogram: Path] = [:]

    static func path(for kind: Pictogram) -> Path {
        if let p = cache[kind] { return p }
        var b = PathBuilder()
        build(kind, &b)
        cache[kind] = b.path
        return b.path
    }

    // swiftlint:disable function_body_length
    private static func build(_ kind: Pictogram, _ b: inout PathBuilder) {
        switch kind {
        case .camel:
            b.poly([(10, 56), (14, 48), (20, 40), (26, 32), (32, 28), (38, 30), (44, 40), (48, 42),
                    (52, 32), (58, 26), (64, 28), (70, 38), (76, 42),
                    (80, 36), (84, 26), (88, 18), (94, 16), (100, 20), (98, 26), (92, 30), (88, 34), (84, 44), (80, 54),
                    (74, 60), (60, 64), (40, 64), (24, 62), (14, 62)])
            b.leg(66, 60, 92, width: 6, lean: 0)
            b.leg(76, 58, 92, width: 6, lean: 3)
            b.leg(22, 60, 92, width: 6, lean: -3)
            b.leg(32, 62, 92, width: 6, lean: 0)
            b.poly([(10, 56), (15, 56), (11, 70), (7, 69)])

        case .horse:
            b.poly([(14, 50), (22, 44), (34, 40), (50, 38), (64, 40), (72, 36), (78, 26), (84, 18), (90, 16), (98, 20), (100, 26), (94, 30),
                    (88, 34), (82, 42), (78, 52), (70, 58), (50, 60), (30, 60), (20, 58)])
            b.poly([(70, 38), (69, 31), (74, 26), (79, 20), (84, 17), (87, 21), (82, 25), (78, 31), (76, 38)])
            b.poly([(85, 18), (87, 11), (90, 17)])
            b.poly([(90, 17), (93, 11), (95, 17)])
            b.poly([(14, 50), (20, 50), (17, 64), (15, 78), (8, 77), (9, 62)])
            b.leg(24, 58, 92, width: 6, lean: -3)
            b.leg(32, 58, 92, width: 6, lean: 1)
            b.leg(62, 58, 92, width: 6, lean: -1)
            b.leg(70, 56, 92, width: 6, lean: 3)

        case .sheep, .ram:
            b.poly([(18, 52), (24, 42), (40, 36), (60, 36), (74, 40), (80, 46), (84, 44), (92, 44), (96, 50), (94, 58), (86, 60), (80, 56),
                    (76, 62), (60, 66), (38, 66), (22, 64)])
            b.leg(26, 64, 90, width: 5)
            b.leg(34, 64, 90, width: 5)
            b.leg(62, 64, 90, width: 5)
            b.leg(70, 64, 90, width: 5)
            if kind == .ram {
                b.ellipse(84, 40, 10, 10)
                b.ellipse(84, 40, 5, 5, hole: true)
            } else {
                b.poly([(86, 44), (79, 40), (83, 49)])
            }

        case .saiga, .gazelle:
            if kind == .saiga {
                b.poly([(16, 50), (22, 44), (36, 40), (54, 40), (66, 42), (74, 38), (78, 30), (84, 26), (90, 26), (96, 32), (98, 42), (94, 48),
                        (88, 50), (82, 48), (78, 52), (72, 60), (56, 64), (32, 64), (20, 60)])
                b.poly([(82, 27), (80, 12), (84, 12), (86, 27)])
                b.poly([(88, 27), (90, 12), (94, 12), (92, 27)])
            } else {
                b.poly([(16, 50), (22, 44), (36, 40), (54, 40), (66, 42), (74, 38), (78, 30), (84, 24), (92, 22), (98, 30), (96, 38), (90, 42),
                        (84, 44), (80, 50), (74, 58), (58, 63), (32, 63), (20, 60)])
                b.poly([(80, 27), (73, 10), (77, 8), (85, 26)])
                b.poly([(86, 26), (84, 8), (88, 8), (91, 26)])
            }
            b.leg(24, 62, 92, width: 5, lean: -2)
            b.leg(32, 62, 92, width: 5, lean: 1)
            b.leg(60, 62, 92, width: 5, lean: -1)
            b.leg(68, 62, 92, width: 5, lean: 2)

        case .deer:
            b.poly([(14, 50), (22, 44), (34, 40), (52, 38), (66, 40), (74, 36), (78, 28), (84, 24), (92, 24), (98, 30), (96, 36), (90, 38),
                    (84, 42), (80, 50), (72, 58), (52, 62), (30, 62), (20, 58)])
            b.bar((82, 25), (76, 6), width: 3)
            b.bar((79, 15), (70, 10), width: 3)
            b.bar((80, 9), (74, 3), width: 3)
            b.bar((88, 25), (94, 6), width: 3)
            b.bar((91, 15), (100, 10), width: 3)
            b.bar((92, 9), (98, 3), width: 3)
            b.poly([(14, 50), (20, 50), (14, 62), (10, 60)])
            b.leg(24, 60, 92, width: 5, lean: -2)
            b.leg(32, 60, 92, width: 5, lean: 1)
            b.leg(60, 60, 92, width: 5, lean: -1)
            b.leg(68, 60, 92, width: 5, lean: 2)

        case .wolf, .dog:
            b.poly([(10, 52), (20, 44), (36, 40), (56, 40), (70, 42), (78, 38), (86, 34), (88, 26), (92, 34), (100, 40), (98, 46), (90, 48),
                    (84, 52), (78, 56), (66, 60), (40, 60), (22, 58), (14, 60)])
            if kind == .wolf {
                b.poly([(92, 34), (95, 27), (97, 35)])
                b.poly([(10, 52), (16, 54), (12, 66), (8, 78), (3, 76), (5, 64)])
            } else {
                b.poly([(84, 34), (80, 44), (87, 44)])
                b.poly([(10, 52), (16, 48), (12, 34), (6, 30), (2, 36), (6, 44), (8, 52)])
            }
            b.leg(22, 58, 90, width: 5, lean: -2)
            b.leg(30, 58, 90, width: 5, lean: 1)
            b.leg(58, 58, 90, width: 5, lean: -1)
            b.leg(66, 58, 90, width: 5, lean: 2)

        case .boar:
            b.poly([(12, 52), (18, 40), (30, 32), (48, 30), (64, 32), (74, 36), (84, 40), (94, 48), (100, 56), (96, 60), (86, 60), (80, 64),
                    (66, 68), (36, 68), (20, 66), (12, 60)])
            b.poly([(30, 32), (32, 23), (37, 31)])
            b.poly([(40, 30), (42, 21), (47, 30)])
            b.poly([(50, 30), (52, 21), (57, 30)])
            b.poly([(94, 55), (98, 49), (100, 55)])
            b.leg(22, 66, 90, width: 6, lean: -1)
            b.leg(30, 66, 90, width: 6, lean: 1)
            b.leg(60, 66, 90, width: 6, lean: -1)
            b.leg(68, 66, 90, width: 6, lean: 1)

        case .eagle:
            b.poly([(2, 44), (14, 34), (28, 30), (40, 32), (48, 28), (52, 20), (58, 17), (66, 19), (71, 26), (63, 28), (72, 34), (86, 36),
                    (98, 44), (88, 48), (72, 50), (66, 52), (64, 64), (60, 74), (52, 76), (44, 74), (38, 64), (36, 52), (30, 50), (14, 48)])

        case .crane:
            b.ellipse(46, 56, 22, 12)
            b.poly([(62, 50), (70, 38), (76, 26), (80, 19), (86, 16), (92, 18), (100, 22), (92, 24), (86, 25), (82, 30), (78, 42), (70, 52)])
            b.poly([(26, 52), (14, 58), (12, 64), (24, 60)])
            b.bar((42, 66), (38, 96), width: 3)
            b.bar((52, 66), (54, 96), width: 3)

        case .bird:
            b.ellipse(48, 56, 20, 12)
            b.ellipse(70, 46, 9, 8)
            b.poly([(78, 44), (90, 48), (78, 50)])
            b.poly([(30, 52), (14, 44), (18, 54), (30, 58)])
            b.bar((44, 68), (42, 88), width: 3)
            b.bar((54, 68), (56, 88), width: 3)

        case .tortoise:
            var dome: [(CGFloat, CGFloat)] = []
            for i in 0...16 {
                let a = CGFloat.pi * (1 - CGFloat(i) / 16)
                dome.append((50 + cos(a) * 34, 62 - sin(a) * 28))
            }
            b.poly(dome)
            b.poly([(84, 58), (94, 52), (100, 58), (94, 66), (84, 64)])
            b.poly([(24, 62), (30, 62), (32, 74), (22, 74)])
            b.poly([(68, 62), (76, 62), (78, 74), (66, 74)])

        case .hedgehog:
            var pts: [(CGFloat, CGFloat)] = [(12, 70)]
            for i in 0...24 {
                let a = CGFloat.pi * (1 - CGFloat(i) / 24)
                let r: CGFloat = i % 2 == 0 ? 1.0 : 0.82
                pts.append((49 + cos(a) * 37 * r, 70 - sin(a) * 34 * r))
            }
            pts += [(86, 66), (100, 70), (88, 74)]
            b.poly(pts)
            b.poly([(26, 70), (34, 70), (34, 78), (26, 78)])
            b.poly([(66, 70), (74, 70), (74, 78), (66, 78)])

        case .marmot:
            b.poly([(34, 92), (30, 70), (34, 50), (42, 36), (50, 22), (58, 20), (66, 26), (68, 36), (62, 44), (68, 60), (72, 80), (70, 92)])
            b.poly([(56, 22), (58, 14), (62, 22)])
            b.poly([(58, 50), (66, 52), (64, 58), (56, 56)])
            b.poly([(30, 88), (16, 84), (10, 90), (20, 94), (34, 94)])

        case .yurt:
            var pts: [(CGFloat, CGFloat)] = [(6, 84), (6, 62)]
            for i in 0...20 {
                let a = CGFloat.pi * (1 - CGFloat(i) / 20)
                pts.append((50 + cos(a) * 44, 62 - sin(a) * 32))
            }
            pts += [(94, 84)]
            b.poly(pts)
            b.poly([(43, 60), (57, 60), (57, 84), (43, 84)], hole: true)
            b.ellipse(50, 22, 7, 7)
            b.ellipse(50, 22, 3.5, 3.5, hole: true)

        case .tree:
            b.poly([(45, 60), (55, 60), (56, 96), (44, 96)])
            b.ellipse(50, 40, 26, 24)
            b.ellipse(34, 48, 14, 12)
            b.ellipse(66, 46, 14, 13)
            b.ellipse(50, 26, 16, 14)

        case .spruce:
            b.poly([(50, 4), (72, 36), (28, 36)])
            b.poly([(50, 22), (80, 58), (20, 58)])
            b.poly([(50, 42), (88, 84), (12, 84)])
            b.poly([(46, 84), (54, 84), (54, 96), (46, 96)])

        case .reeds:
            b.bar((30, 96), (34, 42), width: 3)
            b.bar((50, 96), (50, 32), width: 3)
            b.bar((70, 96), (66, 46), width: 3)
            b.ellipse(34, 34, 3.5, 9)
            b.ellipse(50, 22, 3.5, 10)
            b.ellipse(66, 38, 3.5, 9)
            b.poly([(50, 70), (40, 56), (36, 60), (49, 74)])
            b.poly([(50, 80), (60, 64), (64, 68), (51, 84)])

        case .mausoleum:
            b.poly([(18, 44), (82, 44), (82, 92), (18, 92)])
            var door: [(CGFloat, CGFloat)] = [(40, 92), (40, 66)]
            for i in 0...12 {
                let a = CGFloat.pi * (1 - CGFloat(i) / 12)
                door.append((50 + cos(a) * 10, 66 - sin(a) * 10))
            }
            door.append((60, 92))
            b.poly(door, hole: true)
            var dome: [(CGFloat, CGFloat)] = []
            for i in 0...20 {
                let a = CGFloat.pi * (1 - CGFloat(i) / 20)
                dome.append((50 + cos(a) * 24, 44 - sin(a) * 26))
            }
            b.poly(dome)
            b.poly([(48, 12), (52, 12), (52, 20), (48, 20)])
            b.poly([(8, 52), (16, 52), (16, 92), (8, 92)])
            b.poly([(84, 52), (92, 52), (92, 92), (84, 92)])

        case .ruins:
            b.poly([(18, 40), (30, 36), (32, 92), (18, 92)])
            b.poly([(44, 30), (56, 34), (56, 92), (44, 92)])
            b.poly([(68, 48), (82, 44), (82, 92), (68, 92)])
            b.poly([(14, 30), (60, 26), (60, 36), (14, 40)])
            b.poly([(10, 92), (90, 92), (90, 97), (10, 97)])

        case .tulip:
            b.poly([(48, 48), (52, 48), (53, 96), (47, 96)])
            b.poly([(48, 70), (34, 60), (24, 80), (46, 84)])
            b.poly([(34, 42), (36, 20), (46, 32), (50, 8), (54, 32), (64, 20), (66, 42), (58, 50), (42, 50)])

        case .elder:
            b.ellipse(50, 18, 9, 9)
            b.poly([(40, 14), (50, 0), (60, 14)])
            b.poly([(38, 28), (62, 28), (70, 58), (66, 94), (34, 94), (30, 58)])
            b.bar((78, 14), (78, 96), width: 3.5)
            b.poly([(62, 36), (76, 46), (74, 51), (60, 44)])

        case .dombra:
            b.ellipse(50, 68, 20, 26)
            b.poly([(46, 6), (54, 6), (53, 48), (47, 48)])
            b.poly([(38, 8), (46, 10), (46, 14), (38, 12)])
            b.poly([(54, 12), (62, 10), (62, 14), (54, 16)])

        case .well:
            b.poly([(22, 60), (78, 60), (78, 92), (22, 92)])
            b.poly([(26, 26), (31, 26), (31, 60), (26, 60)])
            b.poly([(69, 26), (74, 26), (74, 60), (69, 60)])
            b.poly([(16, 32), (50, 8), (84, 32), (80, 36), (50, 15), (20, 36)])
            b.bar((50, 30), (50, 52), width: 2)
            b.poly([(43, 50), (57, 50), (55, 62), (45, 62)])

        case .hammer:
            b.poly([(26, 18), (74, 18), (74, 40), (26, 40)])
            b.poly([(46, 40), (54, 40), (57, 94), (43, 94)])

        case .crescent:
            b.ellipse(50, 50, 36, 36)
            b.ellipse(57, 47, 28, 28, hole: true)

        case .snow:
            for i in 0..<6 {
                let a = CGFloat(i) / 6 * 2 * .pi
                let dx = cos(a), dy = sin(a)
                b.stroke([(50, 50), (50 + dx * 38, 50 + dy * 38)])
                let bx = 50 + dx * 24, by = 50 + dy * 24
                let pa = a + .pi / 3, pb = a - .pi / 3
                b.stroke([(bx + cos(pa) * 10, by + sin(pa) * 10), (bx, by), (bx + cos(pb) * 10, by + sin(pb) * 10)])
            }

        case .whirlwind:
            var pts: [(CGFloat, CGFloat)] = []
            for i in 0...60 {
                let t = CGFloat(i) / 60
                let a = t * 4 * .pi
                let r = 3 + 38 * t
                pts.append((50 + cos(a) * r, 50 + sin(a) * r * 0.9))
            }
            b.stroke(pts)

        case .wave:
            for row in 0..<3 {
                var pts: [(CGFloat, CGFloat)] = []
                let y = 32 + CGFloat(row) * 18
                for i in 0...24 {
                    let x = 8 + CGFloat(i) / 24 * 84
                    pts.append((x, y + sin(CGFloat(i) / 24 * 4 * .pi) * 5))
                }
                b.stroke(pts)
            }
        }
    }
    // swiftlint:enable function_body_length
}

/// Отладочный лист со всеми пиктограммами.
struct PictogramSheetView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 18) {
                ForEach(Pictogram.allCases, id: \.self) { kind in
                    VStack(spacing: 6) {
                        PictogramView(kind: kind, size: 56, tint: .gold)
                            .frame(width: 72, height: 72)
                            .background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                        Text(kind.title)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.ash)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.night.ignoresSafeArea())
    }
}
