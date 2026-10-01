import Charts
import SwiftUI

/// Дорожный дневник: отчёт по дням, пройденные места, природа, встречи и испытания.
struct JournalView: View {
    @Environment(GameEngine.self) private var engine
    @State private var tab: JournalTab = .days

    enum JournalTab: CaseIterable, Hashable {
        case days, journeys, places, nature, people, trials

        var title: String {
            switch self {
            case .days: String(localized: "Дни")
            case .journeys: String(localized: "Пути")
            case .places: String(localized: "Места")
            case .nature: String(localized: "Природа")
            case .people: String(localized: "Встречи")
            case .trials: String(localized: "Испытания")
            }
        }
    }

    var body: some View {
        let days = engine.journalDays
        let stats = Journal.stats(days)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenHeader(title: engine.state?.heroName ?? GameEngine.defaultHeroName,
                                 subtitle: String(localized: "День \(engine.dayNumber) · \(Fmt.km(engine.totalKm)) км пути"))

                    RouteProgressPanel(route: engine.route, km: engine.totalKm)
                    StatsGrid(stats: stats)
                    WeekChart(days: days)

                    JournalTabs(selection: $tab)

                    Group {
                        switch tab {
                        case .days: DaysList(days: days)
                        case .journeys: JourneysList()
                        case .places: PlacesTimeline(days: days)
                        case .nature: NatureCollection(days: days)
                        case .people: PeopleList(days: days)
                        case .trials: TrialsList()
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: tab)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            // Полоса под статус-баром, чтобы карточки не уходили под часы.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0).background(Color.night)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
            .navigationDestination(for: JournalDay.self) { DayDetailView(dayKey: $0.key) }
        }
    }
}

// MARK: - Сводка

/// Откуда и куда идёт путник и сколько осталось.
private struct RouteProgressPanel: View {
    let route: Route
    let km: Double

    var body: some View {
        let total = max(route.totalKm, 0.1)
        let progress = min(1, km / total)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(route.stops.first?.name ?? "")
                Spacer(minLength: 8)
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Color.ash)
                Spacer(minLength: 8)
                Text(route.stops.last?.name ?? "")
            }
            .font(.display(16, weight: .regular))
            .foregroundStyle(Color.parchment)
            .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.hairline)
                    Capsule().fill(Color.gold).frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(Fmt.km(km)) из \(Fmt.km(route.totalKm)) км")
                Spacer()
                Text(progress >= 1 ? String(localized: "Путь пройден") : "\(Int((progress * 100).rounded(.down))) %")
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.ash)
            .monospacedDigit()
        }
        .panel()
    }
}

private struct StatsGrid: View {
    let stats: JournalStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            StatCell(value: Fmt.km(stats.walkedKm), unit: String(localized: "км"), caption: String(localized: "пешком"))
            StatCell(value: Fmt.steps(stats.totalSteps), unit: nil, caption: String(localized: "шагов всего"))
            StatCell(value: Fmt.km(stats.averageKm), unit: String(localized: "км"), caption: String(localized: "в среднем за день"))
            StatCell(value: stats.bestDay.map { Fmt.km($0.km) } ?? "—", unit: stats.bestDay == nil ? nil : String(localized: "км"),
                     caption: String(localized: "лучший день"))
            StatCell(value: "\(stats.currentStreak)", unit: nil, caption: String(localized: "активных дней подряд"))
            StatCell(value: "\(stats.activeDays)", unit: "/\(stats.days)", caption: String(localized: "активных дней"))
        }
    }
}

private struct StatCell: View {
    let value: String
    let unit: String?
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.display(24, weight: .regular))
                    .foregroundStyle(Color.gold)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(.display(13, weight: .regular)).foregroundStyle(Color.ash)
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }
}

/// Километры пешком за последние семь дней и средняя линия.
private struct WeekChart: View {
    let days: [JournalDay]

    private struct Bar: Identifiable {
        let id: String
        let date: Date
        let km: Double
        let isToday: Bool
    }

    private var bars: [Bar] {
        let cal = Calendar.current
        let today = days.first?.date ?? cal.startOfDay(for: .now)
        let byKey = Dictionary(uniqueKeysWithValues: days.map { ($0.key, $0) })
        return (0..<7).reversed().compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DayKey.key(date)
            return Bar(id: key, date: date, km: byKey[key]?.walkedKm ?? 0, isToday: offset == 0)
        }
    }

    var body: some View {
        let bars = bars
        let active = bars.filter { $0.km > 0 }
        let average = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.km } / Double(active.count)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: String(localized: "Неделя"))
                Spacer()
                Text("\(Fmt.km(bars.reduce(0) { $0 + $1.km })) км")
                    .font(.display(15, weight: .regular))
                    .foregroundStyle(Color.parchment)
                    .monospacedDigit()
            }
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("day", bar.date, unit: .day), y: .value("km", bar.km), width: .ratio(0.55))
                        .foregroundStyle(bar.isToday ? Color.gold : Color.gold.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if average > 0 {
                    RuleMark(y: .value("avg", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.parchment.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(Color.ash)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel().foregroundStyle(Color.ash)
                }
            }
            .frame(height: 130)
            if average > 0 {
                HStack(spacing: 6) {
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.parchment.opacity(0.5))
                        .frame(width: 16, height: 1)
                    Text("в среднем \(Fmt.km(average)) км в день")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
            }
        }
        .panel()
    }
}

/// Переключатель разделов в цветах приложения (системный сегмент слишком яркий на тёмном фоне).
private struct JournalTabs: View {
    @Binding var selection: JournalView.JournalTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JournalView.JournalTab.allCases, id: \.self) { item in
                    Button {
                        selection = item
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: selection == item ? .semibold : .regular))
                            .foregroundStyle(selection == item ? Color.night : Color.parchment)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selection == item ? Color.gold : Color.panel, in: Capsule())
                            .overlay(Capsule().stroke(selection == item ? Color.clear : Color.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Дни

private struct DaysList: View {
    let days: [JournalDay]

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(days) { day in
                NavigationLink(value: day) { DayCard(day: day) }
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct DayCard: View {
    let day: JournalDay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.isToday ? String(localized: "Сегодня") : day.date.formatted(.dateTime.day().month(.wide)))
                        .font(.display(17, weight: .regular))
                        .foregroundStyle(Color.parchment)
                    Text("День \(day.number) · \(day.date.formatted(.dateTime.weekday(.wide)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ash)
                }
                Spacer()
                if let weather = day.weather {
                    WeatherBadge(weather: weather)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.km(day.dayKm))
                        .font(.display(28, weight: .regular))
                        .foregroundStyle(day.walkedKm > 0 ? Color.gold : Color.ash)
                    Text("км").font(.display(13, weight: .regular)).foregroundStyle(Color.ash)
                }
                Text(String(localized: "\(Fmt.steps(day.steps)) шагов"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ash)
                Spacer()
                if day.isActive {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.gold)
                        .accessibilityLabel(Text("Активный день"))
                }
            }
            .monospacedDigit()

            if let hourly = day.hourly, hourly.contains(where: { $0 > 0 }) {
                HourlySparkline(hourly: hourly)
                    .frame(height: 18)
            }

            if day.hasEvents {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(day.stops) { stop in
                        EventLine(icon: stop.km == 0 ? .walker : .yurt,
                                  text: stop.km == 0 ? String(localized: "Начало пути: \(stop.name)") : String(localized: "Стоянка: \(stop.name)"))
                    }
                    ForEach(day.finishedRoutes, id: \.self) { EventLine(icon: .walker, text: String(localized: "Путь пройден: \($0)")) }
                    ForEach(day.eventsStarted) { EventLine(icon: $0.icon, text: String(localized: "Испытание: \($0.title)")) }
                    ForEach(day.eventsCompleted) { EventLine(icon: $0.icon, text: String(localized: "Пройдено: \($0.title)")) }
                    ForEach(day.eventsFailed) { EventLine(icon: $0.icon, text: String(localized: "Не успели: \($0.title)"), dim: true) }
                }
            }

            if let note = day.note {
                Text(note)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Color.parchment.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .panel()
        .contentShape(Rectangle())
    }
}

private struct EventLine: View {
    let icon: Pictogram
    let text: String
    var dim = false

    var body: some View {
        HStack(spacing: 8) {
            PictogramView(kind: icon, size: 14, tint: dim ? .ash : .gold)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(dim ? Color.ash : Color.parchment)
                .lineLimit(1)
        }
    }
}

struct WeatherBadge: View {
    let weather: WeatherNote

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: weather.symbol)
                .symbolRenderingMode(.hierarchical)
            Text("\(Int(weather.temperature.rounded()))°")
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.gold)
    }
}

/// Шаги по часам одной полоской: видно, когда шёл путник.
private struct HourlySparkline: View {
    let hourly: [Int]

    var body: some View {
        let peak = max(1, hourly.max() ?? 1)
        GeometryReader { geo in
            let w = geo.size.width / 24
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(hourly[h] > 0 ? Color.gold.opacity(0.75) : Color.hairline)
                        .frame(width: max(1, w - 2), height: hourly[h] > 0 ? max(3, geo.size.height * Double(hourly[h]) / Double(peak)) : 2)
                        .frame(width: w, height: geo.size.height, alignment: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Пути

private struct JourneysList: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        let summaries = engine.journeySummaries
        let finished = summaries.filter(\.segment.finished).count
        VStack(alignment: .leading, spacing: 10) {
            Text("Путей: \(summaries.count) · пройдено до конца: \(finished) · всего \(Fmt.km(summaries.reduce(0) { $0 + $1.km })) км")
                .font(.system(size: 13))
                .foregroundStyle(Color.ash)
            ForEach(summaries) { summary in
                NavigationLink {
                    JourneyDetailView(summary: summary)
                } label: {
                    JourneyCard(summary: summary)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                ChangeJourneyButton(compact: true)
                Spacer()
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Места

private struct PlacesTimeline: View {
    @Environment(GameEngine.self) private var engine
    let days: [JournalDay]

    var body: some View {
        let dayOf = Dictionary(days.flatMap { day in day.stops.map { ($0.id, day) } }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 0) {
            ForEach(engine.reachedStops.reversed()) { stop in
                NavigationLink(value: stop) {
                    TimelineRow(isFirst: stop.id == engine.reachedStops.last?.id, dim: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(.display(17, weight: .regular))
                                .foregroundStyle(Color.parchment)
                            Text(stop.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ash)
                                .lineLimit(2)
                            if let day = dayOf[stop.id] {
                                Text("День \(day.number) · \(day.date.formatted(.dateTime.day().month(.abbreviated)))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.gold.opacity(0.8))
                            }
                        }
                    } trailing: {
                        Text("\(Fmt.km(stop.km)) км")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gold)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
            if let next = engine.nextStop {
                TimelineRow(isFirst: false, dim: true) {
                    Text("Впереди: \(next.name), через \(Fmt.km(engine.kmToNextStop)) км")
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Color.ash)
                } trailing: { EmptyView() }
            }
        }
    }
}

private struct TimelineRow<Content: View, Trailing: View>: View {
    let isFirst: Bool
    let dim: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dim ? Color.clear : (isFirst ? Color.gold : Color.gold.opacity(0.5)))
                    .overlay(Circle().stroke(dim ? Color.ash : Color.gold, lineWidth: 1))
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)
                Rectangle().fill(Color.hairline).frame(width: 1).frame(maxHeight: .infinity)
            }
            .frame(width: 10)
            HStack(alignment: .firstTextBaseline) {
                content
                Spacer(minLength: 8)
                trailing
            }
            .padding(.bottom, 18)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Природа

/// Коллекция зверей и растений маршрута: встреченные открыты, остальные ждут впереди.
private struct NatureCollection: View {
    @Environment(GameEngine.self) private var engine
    let days: [JournalDay]
    @State private var selected: Fauna?

    var body: some View {
        let all = uniqueFauna(engine.route.stops.flatMap(\.fauna))
        let seen = Set(engine.seenFauna.map(\.name))
        // Открытые плюс несколько закрытых впереди, чтобы на длинном пути сетка не растягивалась.
        let ahead = all.filter { !seen.contains($0.name) }
        let shown = all.filter { seen.contains($0.name) } + ahead.prefix(6)
        let dayOf = Dictionary(days.flatMap { day in day.fauna.map { ($0.name, day) } }, uniquingKeysWith: { _, b in b })
        VStack(alignment: .leading, spacing: 14) {
            Text("Встречено \(seen.count) из \(all.count)")
                .font(.system(size: 13))
                .foregroundStyle(Color.ash)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(shown) { fauna in
                    let isSeen = seen.contains(fauna.name)
                    Button {
                        guard isSeen else { return }
                        selected = selected == fauna ? nil : fauna
                    } label: {
                        VStack(spacing: 6) {
                            PictogramView(kind: fauna.icon, size: 30, tint: isSeen ? .gold : .ash)
                                .opacity(isSeen ? 1 : 0.25)
                                .frame(height: 34)
                            Text(isSeen ? fauna.name : "?")
                                .font(.system(size: 11))
                                .foregroundStyle(isSeen ? Color.parchment : Color.ash)
                                .multilineTextAlignment(.center)
                                .lineLimit(2, reservesSpace: true)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(selected == fauna ? Color.gold.opacity(0.12) : Color.panel,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected == fauna ? Color.gold.opacity(0.6) : Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            if ahead.count > 6 {
                Text("И ещё \(ahead.count - 6) впереди")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ash)
                    .frame(maxWidth: .infinity)
            }
            if let fauna = selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fauna.name)
                        .font(.display(18, weight: .regular))
                        .foregroundStyle(Color.parchment)
                    if let day = dayOf[fauna.name] {
                        Text("День \(day.number) · \(day.date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.gold.opacity(0.8))
                    }
                    Text(fauna.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ash)
                }
                .panel()
                .transition(.opacity)
            } else if !seen.isEmpty {
                Text("Нажмите на встреченного зверя или растение, чтобы прочитать запись.")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Color.ash)
            }
        }
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    private func uniqueFauna(_ list: [Fauna]) -> [Fauna] {
        var result: [Fauna] = []
        for f in list where !result.contains(where: { $0.name == f.name }) { result.append(f) }
        return result
    }
}

// MARK: - Встречи

private struct PeopleList: View {
    @Environment(GameEngine.self) private var engine
    let days: [JournalDay]

    var body: some View {
        let dayOf = Dictionary(days.flatMap { day in day.stops.map { ($0.id, day) } }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 16) {
            if engine.metPeople.isEmpty {
                Text("Пока никого. Люди, которых путник встретит на стоянках, появятся здесь.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
            }
            ForEach(engine.reachedStops.filter { $0.character != nil }.reversed()) { stop in
                VStack(alignment: .leading, spacing: 8) {
                    Text([stop.name, dayOf[stop.id].map { String(localized: "день \($0.number)") }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gold.opacity(0.8))
                    if let person = stop.character { CharacterCard(character: person) }
                }
                .panel()
            }
        }
    }
}

// MARK: - Испытания

private struct TrialsList: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engine.route.events.isEmpty {
                Text("На этом пути испытаний нет.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
            }
            ForEach(engine.route.events) { event in
                HStack(alignment: .top, spacing: 12) {
                    PictogramView(kind: event.icon, size: 24, tint: statusColor(for: event))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.display(17, weight: .regular))
                            .foregroundStyle(Color.parchment)
                        Text(statusText(for: event))
                            .font(.system(size: 13))
                            .foregroundStyle(statusColor(for: event))
                        if let date = statusDate(for: event) {
                            Text(date.formatted(.dateTime.day().month(.wide)))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ash)
                        }
                    }
                }
            }
        }
    }

    private func statusText(for event: RouteEvent) -> String {
        switch engine.status(of: event) {
        case .none: return String(localized: "Ждёт на \(Fmt.km(event.triggerKm)) км")
        case .active: return String(localized: "Идёт сейчас: \(Fmt.km(event.goalKm)) км за \(Fmt.days(event.days))")
        case .completed: return event.rewardText
        case .failed: return String(localized: "Не успели. Путник справился, но без записи в дневнике")
        }
    }

    private func statusDate(for event: RouteEvent) -> Date? {
        switch engine.status(of: event) {
        case let .active(at, _): at
        case let .completed(at): at
        case let .failed(at): at
        case .none: nil
        }
    }

    private func statusColor(for event: RouteEvent) -> Color {
        switch engine.status(of: event) {
        case .completed, .active: return .gold
        default: return .ash
        }
    }
}

struct SummaryTile: View {
    let icon: Pictogram
    let count: Int
    let total: Int?
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            PictogramView(kind: icon, size: 26)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.display(28, weight: .regular))
                    .foregroundStyle(Color.gold)
                if let total {
                    Text("/\(total)")
                        .font(.display(14, weight: .regular))
                        .foregroundStyle(Color.ash)
                }
            }
            .monospacedDigit()
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
