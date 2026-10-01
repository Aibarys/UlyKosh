import SwiftUI

/// Выбор нового пути в отдельном листе. Прежний путь уходит в архив, дневник остаётся.
struct NewJourneySheet: View {
    @Environment(GameEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let from: Place?

    var body: some View {
        NavigationStack {
            NewJourneyPicker(from: from) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                }
        }
        .presentationBackground(Color.night)
    }
}

/// Выбор пути с пояснением, что станет с нынешним.
struct NewJourneyPicker: View {
    @Environment(GameEngine.self) private var engine
    let from: Place?
    let onStarted: () -> Void

    var body: some View {
        RoutePickerView(startTitle: String(localized: "В путь"), note: note, onStart: { route in
            Task {
                await engine.startJourney(heroName: engine.state?.heroName ?? "", customRoute: route)
                onStarted()
            }
        }, from: from)
    }

    private var note: String? {
        guard engine.state != nil else { return nil }
        if engine.isFinished {
            return String(localized: "Путь \(engine.route.endpoints) пройден и сохранится в дневнике, в разделе «Пути».")
        }
        return String(localized: "Нынешний путь сохранится в дневнике, в разделе «Пути», с пройденными \(Fmt.km(engine.totalKm)) км. Записи дней останутся.")
    }
}

/// Кнопка смены пути: после финиша сразу «Куда дальше?», в пути — выбор, откуда продолжать.
struct ChangeJourneyButton: View {
    @Environment(GameEngine.self) private var engine
    var compact = false
    @State private var sheetFrom: SheetFrom?

    private struct SheetFrom: Identifiable {
        let id = UUID()
        let place: Place?
    }

    var body: some View {
        Group {
            if engine.isFinished {
                Button { sheetFrom = SheetFrom(place: engine.continuePlace) } label: { label(String(localized: "Куда дальше?"), "arrow.triangle.turn.up.right.diamond") }
            } else {
                Menu {
                    if let here = engine.continuePlace {
                        Button {
                            sheetFrom = SheetFrom(place: here)
                        } label: {
                            Label(String(localized: "Свернуть отсюда: \(here.name)"), systemImage: "arrow.triangle.branch")
                        }
                    }
                    Button {
                        sheetFrom = SheetFrom(place: nil)
                    } label: {
                        Label("Начать из другой точки", systemImage: "mappin.and.ellipse")
                    }
                } label: {
                    label(String(localized: "Сменить путь"), "arrow.triangle.branch")
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $sheetFrom) { NewJourneySheet(from: $0.place) }
    }

    private func label(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: compact ? 12 : 14, weight: .medium))
            .foregroundStyle(Color.gold)
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 7 : 10)
            .background(Color.night.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(Color.gold.opacity(0.45)))
    }
}

// MARK: - Финиш

/// Итоги пройденного пути и выбор следующего. Показывается один раз, когда путник дошёл до конца.
struct FinishSummaryView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let summary = engine.currentSummary {
                    VStack(spacing: 22) {
                        PictogramView(kind: .walker, size: 54)
                            .padding(.top, 24)
                        VStack(spacing: 6) {
                            Text("Путь пройден")
                                .font(.display(32, weight: .regular))
                                .foregroundStyle(Color.gold)
                            Text(engine.route.endpoints)
                                .font(.display(18, weight: .regular))
                                .foregroundStyle(Color.parchment)
                                .multilineTextAlignment(.center)
                            Text(engine.route.outro)
                                .font(.system(size: 14))
                                .italic()
                                .foregroundStyle(Color.ash)
                                .multilineTextAlignment(.center)
                                .padding(.top, 6)
                        }
                        JourneyStatsGrid(summary: summary)
                        Button {
                            choosing = true
                        } label: {
                            Text("Куда дальше?")
                                .font(.display(19, weight: .medium))
                                .foregroundStyle(Color.night)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button("Позже") { dismiss() }
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ash)
                        Text("Путник подождёт в конце пути. Следующий путь можно выбрать на вкладке «Маршрут».")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ash)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.night.ignoresSafeArea())
            .navigationDestination(isPresented: $choosing) {
                NewJourneyPicker(from: engine.continuePlace) { dismiss() }
            }
        }
        .presentationBackground(Color.night)
        .onDisappear { engine.markFinishSeen() }
    }
}

/// Плитки итогов одного пути.
struct JourneyStatsGrid: View {
    let summary: JourneySummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            tile("\(summary.days)", String(localized: "дней в пути"))
            tile(Fmt.km(summary.km), String(localized: "км пройдено"))
            tile(Fmt.steps(summary.steps), String(localized: "шагов"))
            tile("\(max(0, summary.stops.count - 1))", String(localized: "стоянок"))
            tile("\(summary.fauna.count)", String(localized: "встреч в природе"))
            tile("\(summary.completedEvents.count)", String(localized: "испытаний пройдено"))
        }
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.display(24, weight: .regular))
                .foregroundStyle(Color.gold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }
}

// MARK: - Архив путей

/// Карточка пути в дневнике.
struct JourneyCard: View {
    let summary: JourneySummary

    var body: some View {
        let seg = summary.segment
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(seg.route.endpoints)
                    .font(.display(17, weight: .regular))
                    .foregroundStyle(Color.parchment)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(seg.finished || seg.isCurrent ? Color.gold : Color.ash)
            }
            Text(dates)
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hairline)
                    Capsule().fill(seg.finished ? Color.gold : Color.gold.opacity(0.6))
                        .frame(width: max(4, geo.size.width * min(1, summary.km / max(seg.route.totalKm, 0.1))))
                }
            }
            .frame(height: 3)
            HStack(spacing: 14) {
                Text("\(Fmt.km(summary.km)) из \(Fmt.km(seg.route.totalKm)) км")
                Text(Fmt.days(summary.days))
                Text("стоянок: \(max(0, summary.stops.count - 1))")
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.ash)
            .monospacedDigit()
        }
        .panel()
        .contentShape(Rectangle())
    }

    private var status: String {
        let seg = summary.segment
        if seg.finished { return String(localized: "Пройден") }
        if seg.isCurrent { return String(localized: "В пути") }
        return String(localized: "Свернули")
    }

    private var dates: String {
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if summary.segment.isCurrent && !summary.segment.finished {
            return String(localized: "с \(summary.firstDay.formatted(f))")
        }
        return "\(summary.firstDay.formatted(f)) — \(summary.lastDay.formatted(f.year()))"
    }
}

/// Подробности пути из архива: карта, итоги, пройденные места.
struct JourneyDetailView: View {
    let summary: JourneySummary

    var body: some View {
        let seg = summary.segment
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(title: seg.route.endpoints, subtitle: seg.route.season)
                if let world = MapWorld.shared {
                    KazakhstanMapView(world: world, route: seg.route, km: summary.km, currentStopId: summary.stops.last?.id,
                                      isFinished: seg.finished, allowsNavigation: false)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                JourneyStatsGrid(summary: summary)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: String(localized: "Пройденные места"))
                    ForEach(summary.stops) { stop in
                        NavigationLink(value: stop) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                        .font(.display(17, weight: .regular))
                                        .foregroundStyle(Color.parchment)
                                    Text(stop.character.map { String(localized: "Встреча: \($0.name)") } ?? stop.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.ash)
                                }
                                Spacer()
                                Text("\(Fmt.km(stop.km)) км")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.gold)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.night.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.night, for: .navigationBar)
    }
}
