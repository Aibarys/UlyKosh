import Foundation

/// Один путь в рамках дневника: текущий или из архива.
struct JourneySegment: Identifiable {
    let id: String
    let route: Route
    /// Начало дня старта.
    let startDate: Date
    /// Километры дня старта, засчитанные предыдущему пути.
    let baselineKm: Double
    /// Когда путь закончился; nil — идёт сейчас.
    let endedAt: Date?
    /// Потолок километров: длина маршрута или сколько успели пройти до смены пути.
    let capKm: Double
    /// Когда путник дошёл до конца маршрута.
    let finishedAt: Date?
    let eventStatus: [String: EventStatus]

    var isCurrent: Bool { endedAt == nil }
    var finished: Bool { finishedAt != nil }
}

/// Один день пути в дневнике.
struct JournalDay: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let date: Date
    let number: Int
    let steps: Int
    /// Пройдено пешком по данным «Здоровья».
    let walkedKm: Double
    /// Сколько путник прошёл сам (по полкилометра за каждый завершённый день).
    let passiveKm: Double
    /// Пройдено по пути к концу этого дня.
    let totalKm: Double
    /// Путь, по которому шёл путник в конце дня.
    let routeTitle: String?
    let hourly: [Int]?
    let stops: [Stop]
    let eventsStarted: [RouteEvent]
    let eventsCompleted: [RouteEvent]
    let eventsFailed: [RouteEvent]
    /// Пути, пройденные до конца в этот день.
    let finishedRoutes: [String]
    let weather: WeatherNote?
    let note: String?
    let isToday: Bool

    /// Активный день: от 5 000 шагов или от 3,5 км пешком.
    var isActive: Bool { steps >= Journal.activeSteps || walkedKm >= 3.5 }
    var dayKm: Double { walkedKm + passiveKm }
    var fauna: [Fauna] { stops.flatMap(\.fauna) }
    var people: [Character] { stops.compactMap(\.character) }

    /// Самый шаговый час дня.
    var peakHour: Int? {
        guard let hourly, let max = hourly.max(), max > 0 else { return nil }
        return hourly.firstIndex(of: max)
    }

    var hasEvents: Bool {
        !stops.isEmpty || !eventsStarted.isEmpty || !eventsCompleted.isEmpty || !eventsFailed.isEmpty || !finishedRoutes.isEmpty
    }
}

struct JournalStats: Equatable {
    var days = 0
    var totalSteps = 0
    var walkedKm = 0.0
    var averageKm = 0.0
    var bestDay: (key: String, km: Double)?
    var currentStreak = 0
    var longestStreak = 0
    var activeDays = 0

    static func == (a: JournalStats, b: JournalStats) -> Bool {
        a.days == b.days && a.totalSteps == b.totalSteps && a.walkedKm == b.walkedKm && a.currentStreak == b.currentStreak
    }
}

/// Итоги одного пути для архива.
struct JourneySummary: Identifiable {
    var id: String { segment.id }
    let segment: JourneySegment
    let firstDay: Date
    let lastDay: Date
    let days: Int
    let km: Double
    let steps: Int
    let stops: [Stop]
    let fauna: [Fauna]
    let people: [Character]
    let completedEvents: [RouteEvent]
    let bestDayKm: Double
}

enum Journal {
    static let activeSteps = 5_000

    /// Пешие километры дня: расстояние из «Здоровья», а без него шаги × длина шага; отладочные шаги через длину шага.
    static func walkedKm(on key: String, in s: GameState) -> Double {
        let health: Double
        if let km = s.healthDistanceKm[key], km > 0 { health = km }
        else { health = Double(s.healthSteps[key] ?? 0) * s.strideMeters / 1000 }
        return health + Double(s.debugSteps[key] ?? 0) * s.strideMeters / 1000
    }

    /// Ход одного пути по дням: сколько пройдено к концу дня и какие стоянки достигнуты.
    struct SegmentDay {
        let key: String
        let date: Date
        let walked: Double
        let passive: Double
        let total: Double
        let stops: [Stop]
    }

    static func progress(of seg: JourneySegment, state s: GameState, today: Date, passivePerDay: Double) -> [SegmentDay] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: seg.startDate)
        let last = cal.startOfDay(for: seg.endedAt ?? today)
        let todayStart = cal.startOfDay(for: today)
        let count = max(1, (cal.dateComponents([.day], from: start, to: last).day ?? 0) + 1)
        var result: [SegmentDay] = []
        var cumulative = 0.0
        var previous = -1.0
        for i in 0..<count {
            guard let date = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let key = DayKey.key(date)
            let walked = max(0, walkedKm(on: key, in: s) - (i == 0 ? seg.baselineKm : 0))
            // Полкилометра за каждый завершённый день пути; день окончания и сегодняшний — без них.
            let passive = (date < todayStart && date < last) ? passivePerDay : 0
            cumulative += walked + passive
            let total = min(cumulative, seg.capKm, seg.route.totalKm)
            let stops = seg.route.stops.filter { $0.km <= total && $0.km > previous }
            result.append(SegmentDay(key: key, date: date, walked: walked, passive: passive, total: total, stops: stops))
            previous = total
        }
        return result
    }

    /// Все дни дневника от сегодняшнего к первому, через все пути.
    static func days(state s: GameState, segments: [JourneySegment], today: Date, passivePerDay: Double) -> [JournalDay] {
        let cal = Calendar.current
        let first = cal.startOfDay(for: min(s.journalStart, segments.map(\.startDate).min() ?? s.journalStart))
        let todayStart = cal.startOfDay(for: today)
        let count = max(1, (cal.dateComponents([.day], from: first, to: todayStart).day ?? 0) + 1)

        // Ход каждого пути, разложенный по дням.
        var byDay: [String: [(JourneySegment, SegmentDay)]] = [:]
        for seg in segments {
            for d in progress(of: seg, state: s, today: today, passivePerDay: passivePerDay) {
                byDay[d.key, default: []].append((seg, d))
            }
        }

        var result: [JournalDay] = []
        for i in 0..<count {
            guard let date = cal.date(byAdding: .day, value: i, to: first) else { continue }
            let key = DayKey.key(date)
            let parts = byDay[key] ?? []
            let dayRange = date..<(cal.date(byAdding: .day, value: 1, to: date) ?? date)
            var started: [RouteEvent] = [], completed: [RouteEvent] = [], failed: [RouteEvent] = []
            var finishedRoutes: [String] = []
            for (seg, _) in parts {
                for event in seg.route.events {
                    switch seg.eventStatus[event.id] {
                    case let .active(at, _): if dayRange.contains(at) { started.append(event) }
                    case let .completed(at): if dayRange.contains(at) { completed.append(event) }
                    case let .failed(at): if dayRange.contains(at) { failed.append(event) }
                    case .none: break
                    }
                }
                if let end = seg.finishedAt, dayRange.contains(end) { finishedRoutes.append(seg.route.endpoints) }
            }
            let lastPart = parts.last
            result.append(JournalDay(
                key: key, date: date, number: i + 1,
                steps: (s.healthSteps[key] ?? 0) + (s.debugSteps[key] ?? 0),
                walkedKm: walkedKm(on: key, in: s),
                passiveKm: parts.map(\.1.passive).max() ?? 0,
                totalKm: lastPart?.1.total ?? 0,
                routeTitle: lastPart?.0.route.endpoints,
                hourly: mergedHourly(s.hourlySteps[key], s.debugHourlySteps[key]),
                stops: parts.flatMap(\.1.stops),
                eventsStarted: started, eventsCompleted: completed, eventsFailed: failed,
                finishedRoutes: finishedRoutes,
                weather: s.weatherLog[key], note: s.dayNotes[key], isToday: i == count - 1))
        }
        return result.reversed()
    }

    /// Итоги пути по его дням.
    static func summary(of seg: JourneySegment, state s: GameState, today: Date, passivePerDay: Double) -> JourneySummary {
        let days = progress(of: seg, state: s, today: today, passivePerDay: passivePerDay)
        let stops = days.flatMap(\.stops)
        var fauna: [Fauna] = []
        for f in stops.flatMap(\.fauna) where !fauna.contains(where: { $0.name == f.name }) { fauna.append(f) }
        let completed = seg.route.events.filter { if case .completed = seg.eventStatus[$0.id] { return true } else { return false } }
        return JourneySummary(
            segment: seg,
            firstDay: days.first?.date ?? seg.startDate,
            lastDay: days.last?.date ?? seg.startDate,
            days: days.count,
            km: days.last?.total ?? 0,
            steps: days.reduce(0) { $0 + (s.healthSteps[$1.key] ?? 0) + (s.debugSteps[$1.key] ?? 0) },
            stops: stops,
            fauna: fauna,
            people: stops.compactMap(\.character),
            completedEvents: completed,
            bestDayKm: days.map(\.walked).max() ?? 0)
    }

    private static func mergedHourly(_ a: [Int]?, _ b: [Int]?) -> [Int]? {
        guard a != nil || b != nil else { return nil }
        let x = a ?? Array(repeating: 0, count: 24), y = b ?? Array(repeating: 0, count: 24)
        return (0..<24).map { x[$0] + y[$0] }
    }

    static func stats(_ days: [JournalDay]) -> JournalStats {
        var st = JournalStats()
        st.days = days.count
        st.totalSteps = days.reduce(0) { $0 + $1.steps }
        st.walkedKm = days.reduce(0) { $0 + $1.walkedKm }
        st.averageKm = days.isEmpty ? 0 : st.walkedKm / Double(days.count)
        if let best = days.max(by: { $0.walkedKm < $1.walkedKm }), best.walkedKm > 0 { st.bestDay = (best.key, best.walkedKm) }
        st.activeDays = days.filter(\.isActive).count
        // days идут от сегодня к началу. Сегодня ещё может стать активным, поэтому неактивное сегодня серию не обрывает.
        var streak = 0
        for (i, day) in days.enumerated() {
            if day.isActive { streak += 1 } else if i == 0 && day.isToday { continue } else { break }
        }
        st.currentStreak = streak
        var run = 0
        for day in days.reversed() {
            run = day.isActive ? run + 1 : 0
            st.longestStreak = max(st.longestStreak, run)
        }
        return st
    }
}
