import Foundation

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
    /// Пройдено с начала пути к концу этого дня.
    let totalKm: Double
    let hourly: [Int]?
    let stops: [Stop]
    let eventsStarted: [RouteEvent]
    let eventsCompleted: [RouteEvent]
    let eventsFailed: [RouteEvent]
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

    var hasEvents: Bool { !stops.isEmpty || !eventsStarted.isEmpty || !eventsCompleted.isEmpty || !eventsFailed.isEmpty }
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

enum Journal {
    static let activeSteps = 5_000

    /// Строит дни пути из сохранённого состояния. Километры считаются так же, как в движке.
    static func days(state s: GameState, route: Route, today: Date, passivePerDay: Double) -> [JournalDay] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: s.startDate)
        let todayStart = cal.startOfDay(for: today)
        let count = max(1, (cal.dateComponents([.day], from: start, to: todayStart).day ?? 0) + 1)

        var result: [JournalDay] = []
        var cumulative = 0.0
        var previousTotal = -1.0
        for i in 0..<count {
            guard let date = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let key = DayKey.key(date)
            let isToday = i == count - 1
            let walked: Double = {
                let health: Double
                if let km = s.healthDistanceKm[key], km > 0 { health = km }
                else { health = Double(s.healthSteps[key] ?? 0) * s.strideMeters / 1000 }
                return health + Double(s.debugSteps[key] ?? 0) * s.strideMeters / 1000
            }()
            // Полкилометра путник проходит сам за каждый завершённый день.
            let passive = isToday ? 0 : passivePerDay
            cumulative += walked + passive
            let total = min(cumulative, route.totalKm)
            let stops = route.stops.filter { stop in
                stop.km <= total && stop.km > previousTotal && !(i > 0 && stop.km == 0)
            }
            let dayRange = date..<(cal.date(byAdding: .day, value: 1, to: date) ?? date)
            var started: [RouteEvent] = [], completed: [RouteEvent] = [], failed: [RouteEvent] = []
            for event in route.events {
                switch s.eventStatus[event.id] {
                case let .active(at, _): if dayRange.contains(at) { started.append(event) }
                case let .completed(at): if dayRange.contains(at) { completed.append(event) }
                case let .failed(at): if dayRange.contains(at) { failed.append(event) }
                case .none: break
                }
            }
            result.append(JournalDay(
                key: key, date: date, number: i + 1,
                steps: (s.healthSteps[key] ?? 0) + (s.debugSteps[key] ?? 0),
                walkedKm: walked, passiveKm: passive, totalKm: total,
                hourly: mergedHourly(s.hourlySteps[key], s.debugHourlySteps[key]),
                stops: stops, eventsStarted: started, eventsCompleted: completed, eventsFailed: failed,
                weather: s.weatherLog[key], note: s.dayNotes[key], isToday: isToday))
            previousTotal = total
        }
        return result.reversed()
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
        // days идут от сегодня к началу. Текущая серия: сегодня ещё может стать активным, поэтому его пропускаем, если он пока нет.
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
