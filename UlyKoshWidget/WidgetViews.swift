import SwiftUI
import WidgetKit

struct KmEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WidgetRootView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KmEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemSmall: SmallWidgetView(s: s)
            case .systemMedium: MediumWidgetView(s: s)
            case .accessoryCircular: CircularWidgetView(s: s)
            case .accessoryRectangular: RectangularWidgetView(s: s)
            case .accessoryInline: InlineWidgetView(s: s)
            default: SmallWidgetView(s: s)
            }
        } else {
            EmptyStateView(family: family)
        }
    }
}

// MARK: - Домашний экран

struct SmallWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PictogramView(kind: .rider, size: 18, tint: .gold)
                Text("Сегодня")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ash)
                Spacer()
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.km(s.kmToday))
                    .font(.display(40))
                    .foregroundStyle(Color.gold)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("км")
                    .font(.display(13, weight: .regular))
                    .foregroundStyle(Color.gold)
            }
            Text("\(s.stepsToday.formatted()) шагов")
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
            Spacer(minLength: 4)
            if s.isFinished {
                Text("Кочевье окончено")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.parchment)
            } else if let next = s.nextStopName {
                Text("до стоянки \(next) \(Fmt.km(s.kmToNextStop)) км")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.parchment)
                    .lineLimit(2)
            }
        }
    }
}

struct MediumWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    PictogramView(kind: .rider, size: 18, tint: .gold)
                    Text("Сегодня")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ash)
                }
                Spacer(minLength: 2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.km(s.kmToday))
                        .font(.display(42))
                        .foregroundStyle(Color.gold)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("км")
                        .font(.display(13, weight: .regular))
                        .foregroundStyle(Color.gold)
                }
                Text("\(s.stepsToday.formatted()) шагов")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ash)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("День \(s.dayNumber) · \(s.routeTitle)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ash)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.km(s.kmTotal))
                        .font(.display(22, weight: .regular))
                        .foregroundStyle(Color.parchment)
                    Text("из \(Fmt.km(s.routeTotalKm)) км")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ash)
                }
                ProgressView(value: min(s.kmTotal, s.routeTotalKm), total: s.routeTotalKm)
                    .tint(Color.gold)
                    .scaleEffect(y: 0.7)
                Spacer(minLength: 0)
                if s.isFinished {
                    Text("Кочевье окончено")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.parchment)
                } else if let next = s.nextStopName {
                    Text(next)
                        .font(.display(14, weight: .regular))
                        .foregroundStyle(Color.parchment)
                        .lineLimit(1)
                    Text("через \(Fmt.km(s.kmToNextStop)) км · \(s.regionName)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ash)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Экран блокировки

struct CircularWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        Gauge(value: min(s.kmTotal, s.routeTotalKm), in: 0...max(s.routeTotalKm, 1)) {
            PictogramView(kind: .rider, size: 12, tint: .primary)
        } currentValueLabel: {
            VStack(spacing: -2) {
                Text(Fmt.km(s.kmToday))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                Text("км")
                    .font(.system(size: 8))
            }
        }
        .gaugeStyle(.accessoryCircular)
    }
}

struct RectangularWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                PictogramView(kind: .rider, size: 12, tint: .primary)
                Text("Ұлы Көш")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("\(Fmt.km(s.kmToday)) км сегодня")
                .font(.system(size: 14, weight: .medium, design: .serif))
            if let next = s.nextStopName, !s.isFinished {
                Text("до \(next) \(Fmt.km(s.kmToNextStop)) км")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(Fmt.km(s.kmTotal)) из \(Fmt.km(s.routeTotalKm)) км")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineWidgetView: View {
    let s: WidgetSnapshot

    var body: some View {
        if let next = s.nextStopName, !s.isFinished {
            Text("\(Fmt.km(s.kmToday)) км · до \(next) \(Fmt.km(s.kmToNextStop)) км")
        } else {
            Text("\(Fmt.km(s.kmToday)) км сегодня")
        }
    }
}

struct EmptyStateView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Ұлы Көш: начните кочевье")
        case .accessoryCircular:
            PictogramView(kind: .rider, size: 22, tint: .primary)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Ұлы Көш").font(.system(size: 12, weight: .semibold))
                Text("Откройте приложение и начните кочевье").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                PictogramView(kind: .rider, size: 28, tint: .gold)
                Spacer()
                Text("Ұлы Көш")
                    .font(.display(18, weight: .regular))
                    .foregroundStyle(Color.gold)
                Text("Откройте приложение и начните кочевье")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ash)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Отладочный лист: все размеры виджета с текущим снимком.
struct WidgetPreviewSheet: View {
    var body: some View {
        let snapshot = WidgetSnapshot.load() ?? .placeholder
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Маленький").font(.system(size: 11)).foregroundStyle(Color.ash)
                    SmallWidgetView(s: snapshot)
                        .padding(16)
                        .frame(width: 170, height: 170)
                        .background(Color.night, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.hairline))
                    Text("Средний").font(.system(size: 11)).foregroundStyle(Color.ash)
                    MediumWidgetView(s: snapshot)
                        .padding(16)
                        .frame(width: 364, height: 170)
                        .background(Color.night, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.hairline))
                }
                Text("Экран блокировки").font(.system(size: 11)).foregroundStyle(Color.ash)
                HStack(spacing: 14) {
                    CircularWidgetView(s: snapshot)
                        .frame(width: 72, height: 72)
                    RectangularWidgetView(s: snapshot)
                        .frame(width: 170, height: 72)
                }
                .padding(12)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                InlineWidgetView(s: snapshot)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white.opacity(0.12), in: Capsule())
                Text("Пусто").font(.system(size: 11)).foregroundStyle(Color.ash)
                EmptyStateView(family: .systemSmall)
                    .padding(16)
                    .frame(width: 170, height: 170)
                    .background(Color.night, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.hairline))
            }
            .padding(20)
        }
        .background(Color(white: 0.12).ignoresSafeArea())
    }
}
