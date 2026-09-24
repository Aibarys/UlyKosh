import Foundation
import SwiftUI

enum Season: CaseIterable {
    case spring, summer, autumn, winter

    static func current(_ date: Date = .now) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    var title: String {
        switch self {
        case .spring: return String(localized: "Весна · көктем")
        case .summer: return String(localized: "Лето · жаз")
        case .autumn: return String(localized: "Осень · күз")
        case .winter: return String(localized: "Зима · қыс")
        }
    }

    /// Приблизительные восход и закат для широты Сарыарқи по месяцам, в часах местного времени.
    static func sunHours(_ date: Date = .now) -> (rise: Double, set: Double) {
        let table: [(Double, Double)] = [
            (8.6, 17.4), (8.0, 18.3), (7.0, 19.1), (5.9, 19.9), (5.1, 20.6), (4.7, 21.1),
            (4.9, 21.0), (5.7, 20.2), (6.5, 19.1), (7.3, 18.1), (8.1, 17.3), (8.6, 17.1)
        ]
        return table[Calendar.current.component(.month, from: date) - 1]
    }
}

enum SkyPhase {
    case night, dawn, day, dusk

    static func current(_ date: Date = .now) -> SkyPhase {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let sun = Season.sunHours(date)
        switch hour {
        case (sun.rise - 1.0)..<(sun.rise + 0.8): return .dawn
        case (sun.rise + 0.8)..<(sun.set - 0.9): return .day
        case (sun.set - 0.9)..<(sun.set + 0.8): return .dusk
        default: return .night
        }
    }

    func colors(for season: Season) -> [Color] {
        switch (self, season) {
        case (.night, .winter):
            return [Color(red: 0.04, green: 0.05, blue: 0.09), Color(red: 0.08, green: 0.11, blue: 0.17), Color(red: 0.16, green: 0.19, blue: 0.24)]
        case (.night, _):
            return [Color(red: 0.03, green: 0.06, blue: 0.10), Color(red: 0.06, green: 0.13, blue: 0.17), Color(red: 0.11, green: 0.19, blue: 0.21)]

        case (.dawn, .autumn):
            return [Color(red: 0.22, green: 0.30, blue: 0.45), Color(red: 0.62, green: 0.60, blue: 0.62), Color(red: 0.95, green: 0.72, blue: 0.45), Color(red: 0.90, green: 0.55, blue: 0.35)]
        case (.dawn, .winter):
            return [Color(red: 0.30, green: 0.36, blue: 0.50), Color(red: 0.66, green: 0.70, blue: 0.80), Color(red: 0.95, green: 0.84, blue: 0.75), Color(red: 0.92, green: 0.70, blue: 0.62)]
        case (.dawn, _):
            return [Color(red: 0.16, green: 0.33, blue: 0.53), Color(red: 0.47, green: 0.65, blue: 0.79), Color(red: 0.95, green: 0.77, blue: 0.55), Color(red: 0.91, green: 0.63, blue: 0.60)]

        case (.day, .spring):
            return [Color(red: 0.20, green: 0.45, blue: 0.70), Color(red: 0.55, green: 0.74, blue: 0.88), Color(red: 0.86, green: 0.90, blue: 0.91)]
        case (.day, .summer):
            return [Color(red: 0.12, green: 0.38, blue: 0.72), Color(red: 0.42, green: 0.66, blue: 0.88), Color(red: 0.90, green: 0.90, blue: 0.82)]
        case (.day, .autumn):
            return [Color(red: 0.30, green: 0.47, blue: 0.64), Color(red: 0.66, green: 0.72, blue: 0.74), Color(red: 0.90, green: 0.80, blue: 0.62)]
        case (.day, .winter):
            return [Color(red: 0.55, green: 0.62, blue: 0.72), Color(red: 0.76, green: 0.80, blue: 0.85), Color(red: 0.92, green: 0.92, blue: 0.93)]

        case (.dusk, .autumn):
            return [Color(red: 0.18, green: 0.14, blue: 0.24), Color(red: 0.55, green: 0.28, blue: 0.28), Color(red: 0.90, green: 0.50, blue: 0.24), Color(red: 0.96, green: 0.74, blue: 0.40)]
        case (.dusk, .winter):
            return [Color(red: 0.18, green: 0.18, blue: 0.30), Color(red: 0.48, green: 0.36, blue: 0.50), Color(red: 0.90, green: 0.62, blue: 0.55), Color(red: 0.96, green: 0.84, blue: 0.75)]
        case (.dusk, _):
            return [Color(red: 0.15, green: 0.13, blue: 0.25), Color(red: 0.45, green: 0.24, blue: 0.35), Color(red: 0.86, green: 0.53, blue: 0.34), Color(red: 0.95, green: 0.78, blue: 0.55)]
        }
    }

    /// Цвет земли: летом и весной чёрный силуэт, осенью тёмно-бурый, зимой снег.
    func groundColor(for season: Season) -> Color {
        switch season {
        case .winter:
            return self == .night ? Color(red: 0.62, green: 0.66, blue: 0.74) : Color(red: 0.90, green: 0.91, blue: 0.93)
        case .autumn:
            return Color(red: 0.08, green: 0.06, blue: 0.04)
        default:
            return .black
        }
    }

    func farColor(for season: Season) -> Color {
        switch season {
        case .winter:
            return self == .night ? Color(red: 0.40, green: 0.44, blue: 0.54) : Color(red: 0.70, green: 0.74, blue: 0.80)
        case .autumn:
            return Color(red: 0.22, green: 0.16, blue: 0.10).opacity(0.75)
        default:
            return Color.black.opacity(0.5)
        }
    }

    /// Дымка над горизонтом: осенью пыльно-золотая, летом марево, иначе нет.
    func haze(for season: Season) -> Color? {
        switch season {
        case .autumn: return Color(red: 0.85, green: 0.62, blue: 0.30).opacity(0.18)
        case .summer: return self == .day ? Color(red: 1.0, green: 0.92, blue: 0.70).opacity(0.10) : nil
        default: return nil
        }
    }
}

/// Отладочный лист: все сезоны и фазы дня для одной местности.
struct SeasonSheetView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(Season.allCases, id: \.self) { season in
                    Text(season.title)
                        .font(.display(16, weight: .regular))
                        .foregroundStyle(Color.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        ForEach([SkyPhase.dawn, .day, .dusk, .night], id: \.self) { phase in
                            SceneView(terrain: .pasture, phase: phase, season: season)
                                .frame(height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
    }
}

/// Отладочный лист: все местности с караваном днём, для поиска наложений.
struct TerrainSheetView: View {
    private let terrains: [Terrain] = [.river, .ruins, .mountains, .desert, .ford, .mausoleum, .pasture]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(terrains, id: \.self) { terrain in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(describing: terrain))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ash)
                        SceneView(terrain: terrain, phase: .day, season: .current())
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
    }
}
