import Foundation
import Observation
import WidgetKit

struct ActiveEvent {
    let event: RouteEvent
    let startedAt: Date
    let startKm: Double
    let coveredKm: Double
    let daysLeft: Int

    var progress: Double { min(1, coveredKm / event.goalKm) }
}

@MainActor
@Observable
final class GameEngine {
    /// Путник идёт всегда, даже если хозяин сегодня не ходил: чуть-чуть, чтобы не было чувства вины.
    static let passiveKmPerDay = 0.5

    enum HealthStatus { case unknown, unavailable, requested }

    private(set) var state: GameState?
    private(set) var isLoading = true
    private(set) var healthStatus: HealthStatus = .unknown
    private(set) var lastSync: Date?
    var lastError: String?
    /// Источники, которые видны в «Здоровье», и их шаги за сегодня (для экрана настроек).
    private(set) var healthSources: [HealthSource] = []
    private(set) var stepsTodayBySource: [String: Int] = [:]

    private let store: StateStore
    private let health = HealthKitStepSource()
    private let notifications = NotificationService.shared
    /// Текущее время; в тестах подменяется.
    let clock: () -> Date
    /// Канал уведомлений; в тестах перехватывается.
    var notify: (_ id: String, _ title: String, _ body: String) -> Void
    /// В тестах отключает обращение к HealthKit и виджету.
    private let isolated: Bool

    init() {
        store = StateStore()
        clock = { .now }
        isolated = false
        notify = { id, title, body in NotificationService.shared.post(id: id, title: title, body: body) }
    }

    /// Изолированный движок для тестов: своя папка состояния, свои часы, без HealthKit.
    init(storeDirectory: URL, clock: @escaping () -> Date) {
        store = StateStore(directory: storeDirectory)
        self.clock = clock
        isolated = true
        notify = { _, _, _ in }
    }

    private var now: Date { clock() }

    /// Текущий маршрут; до старта — великое кочевье по сезону.
    var route: Route {
        if let s = state {
            if s.routeId == CustomRoute.routeId, let custom = s.customRoute { return customRoute(custom) }
            if let r = Routes.byId(s.routeId) { return r }
        }
        return Routes.forStart(now)
    }

    @ObservationIgnored private var customCache: [CustomRoute: Route] = [:]
    @ObservationIgnored private var cacheLanguage: String?

    private func customRoute(_ custom: CustomRoute) -> Route {
        let language = Bundle.main.preferredLocalizations.first
        if language != cacheLanguage { customCache = [:]; cacheLanguage = language }
        if let cached = customCache[custom] { return cached }
        let built = RouteBuilder.makeRoute(custom)
        customCache[custom] = built
        return built
    }

    /// Маршрут пути из архива.
    func route(of record: JourneyRecord) -> Route {
        if record.routeId == CustomRoute.routeId, let custom = record.customRoute { return customRoute(custom) }
        return Routes.byId(record.routeId) ?? Routes.all[0]
    }
    private var loaded = false
    private var suppressNotificationsOnce = false

    // MARK: - Жизненный цикл

    /// Вызывается и из App.init (в том числе при фоновом запуске системой), и из RootView. Выполняется один раз.
    func bootstrap() async {
        await load()
        startObservingIfPossible()
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        state = store.load()
        isLoading = false
        if isolated { return }
        if !health.isAvailable {
            healthStatus = .unavailable
        } else if state?.healthRequested == true {
            healthStatus = .requested
        }
        if state != nil {
            // Повторный запрос ничего не показывает, если доступ уже определён, но подхватывает новые типы данных.
            if health.isAvailable, state?.healthRequested == true {
                try? await health.requestAuthorization()
            }
            await syncSteps()
        }
    }

    private func startObservingIfPossible() {
        guard state != nil, health.isAvailable, !isolated else { return }
        Task { await health.enableBackgroundDelivery() }
        health.startObserving { [weak self] in
            await self?.backgroundSync()
        }
    }

    private func backgroundSync() async {
        await load()
        await syncSteps()
    }

    static var defaultHeroName: String { String(localized: "Жолаушы") }

    /// Начинает путь: великое кочевье по сезону, выбранное кочевье или свой маршрут.
    /// Прежний путь уходит в архив, дневник и шаги остаются.
    func startJourney(heroName: String, routeId: String? = nil, customRoute: CustomRoute? = nil) async {
        let name = heroName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = state
        var fresh = GameState(
            routeId: customRoute != nil ? CustomRoute.routeId : (routeId ?? Routes.forStart(now).id),
            heroName: name.isEmpty ? (previous?.heroName ?? Self.defaultHeroName) : name,
            startDate: Calendar.current.startOfDay(for: now),
            customRoute: customRoute
        )
        if let previous {
            fresh.strideMeters = previous.strideMeters
            fresh.sourceSettings = previous.sourceSettings
            fresh.healthRequested = previous.healthRequested
            fresh.journalStart = previous.journalStart
            fresh.healthSteps = previous.healthSteps
            fresh.healthDistanceKm = previous.healthDistanceKm
            fresh.hourlySteps = previous.hourlySteps
            fresh.debugSteps = previous.debugSteps
            fresh.debugHourlySteps = previous.debugHourlySteps
            fresh.weatherLog = previous.weatherLog
            fresh.dayNotes = previous.dayNotes
            fresh.history = previous.history
            if let record = archiveRecord(of: previous) { fresh.history.append(record) }
            // Шаги, сделанные сегодня до старта, остаются прежнему пути: новый начинается с нуля.
            fresh.startBaselineKm = Journal.walkedKm(on: DayKey.key(now), in: previous)
        }
        state = fresh
        persist()
        suppressNotificationsOnce = true
        guard !isolated else { evaluateAndNotify(); persist(); return }
        await requestHealthAccess()
        await notifications.requestAuthorization()
        startObservingIfPossible()
    }

    /// Запись прежнего пути для архива; путь, на котором не сделано ни шага, не сохраняется.
    private func archiveRecord(of s: GameState) -> JourneyRecord? {
        let km = min(rawKm(s), route.totalKm)
        guard s.finishedAt != nil || km >= 0.1 else { return nil }
        return JourneyRecord(
            id: UUID().uuidString,
            routeId: s.routeId,
            customRoute: s.customRoute,
            startDate: s.startDate,
            startBaselineKm: s.startBaselineKm,
            endedAt: s.finishedAt ?? now,
            km: s.finishedAt != nil ? route.totalKm : km,
            finished: s.finishedAt != nil,
            eventStatus: s.eventStatus)
    }

    func markFinishSeen() {
        guard state?.finishSeen == false else { return }
        state?.finishSeen = true
        persist()
    }

    func requestHealthAccess() async {
        guard health.isAvailable else {
            healthStatus = .unavailable
            return
        }
        do {
            try await health.requestAuthorization()
            healthStatus = .requested
            state?.healthRequested = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await syncSteps()
    }

    func syncSteps() async {
        guard let snapshot = state else { return }
        if health.isAvailable, !isolated {
            // Шаги и расстояние читаем независимо: отказ по одному типу не должен ломать другой.
            async let stepsResult: Result<[Date: [String: Double]], Error> = {
                do { return .success(try await health.hourlyStepsBySource(from: snapshot.journalStart, to: .now)) } catch { return .failure(error) }
            }()
            async let distanceResult: Result<[Date: [String: Double]], Error> = {
                do { return .success(try await health.hourlyDistanceKmBySource(from: snapshot.journalStart, to: .now)) } catch { return .failure(error) }
            }()
            let (steps, distance) = await (stepsResult, distanceResult)
            if let list = try? await health.sources() { healthSources = list }
            // Пока ждали HealthKit, состояние могло измениться, поэтому перечитываем.
            guard var current = state else { return }
            let hourlySteps = (try? steps.get()) ?? [:]
            let hourlyKm = (try? distance.get()) ?? [:]
            let daily = Self.aggregate(steps: hourlySteps, km: hourlyKm, settings: current.sourceSettings, stride: current.strideMeters, today: now)
            current.healthSteps = daily.steps
            current.healthDistanceKm = daily.km
            current.hourlySteps = daily.hourly
            stepsTodayBySource = daily.todayBySource
            state = current
            switch (steps, distance) {
            case (.failure(let e), .failure):
                lastError = e.localizedDescription
            default:
                lastSync = .now
                lastError = nil
            }
        }
        evaluateAndNotify()
        persist()
    }

    func resetJourney() {
        state = nil
        store.clear()
        publishWidgetSnapshot()
    }

    // MARK: - Настройки и отладка

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state?.heroName != trimmed else { return }
        state?.heroName = trimmed
        persist()
    }

    func setStride(_ meters: Double) {
        state?.strideMeters = meters
        evaluateAndNotify()
        persist()
        Task { await syncSteps() }
    }

    func addDebugSteps(_ steps: Int) {
        guard var current = state else { return }
        current.debugSteps[DayKey.key(now), default: 0] += steps
        var hours24 = current.debugHourlySteps[DayKey.key(now)] ?? Array(repeating: 0, count: 24)
        hours24[Calendar.current.component(.hour, from: now)] += steps
        current.debugHourlySteps[DayKey.key(now)] = hours24
        state = current
        evaluateAndNotify()
        persist()
    }

    // MARK: - Учёт источников

    struct DailyTotals {
        var steps: [String: Int] = [:]
        var km: [String: Double] = [:]
        var todayBySource: [String: Int] = [:]
        var hourly: [String: [Int]] = [:]
    }

    /// Сводит почасовые данные по источникам в дневные шаги и километры.
    /// За час берётся наибольшее число шагов среди включённых источников (несколько устройств считают одну прогулку).
    /// Расстояние берётся от источников, которые его пишут; шаги сверх их шагов (дорожка, браслет без телефона)
    /// переводятся по длине шага. Источники с ночным фильтром не учитываются в тихие часы.
    static func aggregate(steps: [Date: [String: Double]], km: [Date: [String: Double]],
                          settings: [String: SourceSetting], stride: Double, today: Date = .now) -> DailyTotals {
        var totals = DailyTotals()
        let calendar = Calendar.current
        let todayKey = DayKey.key(today)
        let distanceSources = Set(km.values.flatMap(\.keys))
        let hours = Set(steps.keys).union(km.keys)

        func allowed(_ source: String, at hour: Date) -> Bool {
            let setting = settings[source] ?? SourceSetting()
            guard setting.enabled else { return false }
            if setting.nightFilter {
                let h = calendar.component(.hour, from: hour)
                if h >= 23 || h < 6 { return false }
            }
            return true
        }

        for hour in hours {
            let dayKey = DayKey.key(hour)
            let stepsHere = (steps[hour] ?? [:]).filter { allowed($0.key, at: hour) }
            let kmHere = (km[hour] ?? [:]).filter { allowed($0.key, at: hour) }

            let dedupedSteps = stepsHere.values.max() ?? 0
            let distanceKm = kmHere.values.reduce(0, +)
            let stepsCoveredByDistance = stepsHere.filter { distanceSources.contains($0.key) }.values.max() ?? 0
            let extraSteps = max(0, dedupedSteps - stepsCoveredByDistance)
            let kmHour = distanceKm + extraSteps * stride / 1000

            totals.steps[dayKey, default: 0] += Int(dedupedSteps.rounded())
            totals.km[dayKey, default: 0] += kmHour
            var hours24 = totals.hourly[dayKey] ?? Array(repeating: 0, count: 24)
            hours24[calendar.component(.hour, from: hour)] += Int(dedupedSteps.rounded())
            totals.hourly[dayKey] = hours24
            if dayKey == todayKey {
                for (source, value) in steps[hour] ?? [:] {
                    totals.todayBySource[source, default: 0] += Int(value.rounded())
                }
            }
        }
        return totals
    }

    /// Подаёт данные «Здоровья» напрямую, минуя HealthKit. Для тестов.
    func ingest(hourlySteps: [Date: [String: Double]], hourlyKm: [Date: [String: Double]]) {
        guard var current = state else { return }
        let daily = Self.aggregate(steps: hourlySteps, km: hourlyKm, settings: current.sourceSettings, stride: current.strideMeters, today: now)
        current.healthSteps = daily.steps
        current.healthDistanceKm = daily.km
        current.hourlySteps = daily.hourly
        stepsTodayBySource = daily.todayBySource
        state = current
        evaluateAndNotify()
        persist()
    }

    // MARK: - Дневник

    /// Записывает погоду, которую путник видел сегодня.
    func logWeather(_ note: WeatherNote) {
        guard state != nil else { return }
        state?.weatherLog[DayKey.key(now)] = note
        persist()
    }

    func setNote(_ text: String, for dayKey: String) {
        guard state != nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state?.dayNotes[dayKey] = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    /// Текущий путь как часть дневника.
    var currentSegment: JourneySegment? {
        guard let s = state else { return nil }
        return JourneySegment(id: "current", route: route, startDate: s.startDate, baselineKm: s.startBaselineKm,
                              endedAt: nil, capKm: route.totalKm, finishedAt: s.finishedAt, eventStatus: s.eventStatus)
    }

    /// Пути из архива, от старых к новым.
    var pastSegments: [JourneySegment] {
        (state?.history ?? []).map { r in
            JourneySegment(id: r.id, route: route(of: r), startDate: r.startDate, baselineKm: r.startBaselineKm,
                           endedAt: r.endedAt, capKm: r.km, finishedAt: r.finished ? r.endedAt : nil, eventStatus: r.eventStatus)
        }
    }

    /// Дни дневника от сегодняшнего к первому, через все пути.
    var journalDays: [JournalDay] {
        guard let s = state else { return [] }
        return Journal.days(state: s, segments: pastSegments + [currentSegment].compactMap { $0 }, today: now, passivePerDay: Self.passiveKmPerDay)
    }

    /// Итоги путей: текущий первым, дальше архив от новых к старым.
    var journeySummaries: [JourneySummary] {
        guard let s = state else { return [] }
        return ([currentSegment].compactMap { $0 } + pastSegments.reversed()).map {
            Journal.summary(of: $0, state: s, today: now, passivePerDay: Self.passiveKmPerDay)
        }
    }

    /// Итоги текущего пути (для экрана финиша).
    var currentSummary: JourneySummary? {
        guard let s = state, let seg = currentSegment else { return nil }
        return Journal.summary(of: seg, state: s, today: now, passivePerDay: Self.passiveKmPerDay)
    }

    /// Где сейчас путник на местности.
    var currentCoordinate: GeoPoint { route.coordinate(atKm: totalKm) }

    /// Пункт, откуда продолжать: после финиша — конечная точка, в пути — ближайший к путнику населённый пункт.
    var continuePlace: Place? {
        if isFinished, let custom = state?.customRoute, let place = PlaceStore.shared.place(custom.toId) { return place }
        return PlaceStore.shared.nearest(to: currentCoordinate)
    }

    var journalStats: JournalStats { Journal.stats(journalDays) }

    #if DEBUG
    /// Отладка (`-journalDemo`): переносит старт на 10 дней назад и заполняет дни шагами, погодой и заметками.
    func seedJournalDemo() {
        guard var s = state else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        s.startDate = cal.date(byAdding: .day, value: -9, to: today) ?? today
        s.journalStart = min(s.journalStart, s.startDate)
        s.startBaselineKm = 0
        s.debugSteps = [:]
        s.debugHourlySteps = [:]
        let totals = [7_200, 11_500, 3_100, 9_800, 14_300, 6_400, 0, 8_900, 12_700, 4_200]
        let weather = [("sun.max", "clear", 14.0), ("cloud.sun", "partlyCloudy", 11.0), ("cloud.rain", "rain", 7.0),
                       ("cloud", "cloudy", 9.0), ("wind", "windy", 6.0), ("cloud.fog", "foggy", 4.0),
                       ("cloud.drizzle", "drizzle", 5.0), ("sun.max", "clear", 12.0), ("cloud.sun", "mostlyClear", 13.0), ("cloud", "cloudy", 10.0)]
        let shape = [0, 0, 0, 0, 0, 0, 1, 4, 9, 5, 3, 2, 6, 3, 2, 2, 3, 6, 10, 8, 4, 2, 0, 0]
        let weight = Double(shape.reduce(0, +))
        for i in 0..<10 {
            guard let date = cal.date(byAdding: .day, value: i, to: s.startDate) else { continue }
            let key = DayKey.key(date)
            let hourly = shape.map { Int(Double(totals[i]) * Double($0) / weight) }
            s.debugSteps[key] = hourly.reduce(0, +)
            s.debugHourlySteps[key] = hourly
            let w = weather[i]
            s.weatherLog[key] = WeatherNote(temperature: w.2, condition: w.1, symbol: w.0, place: "Павлодар")
        }
        s.dayNotes[DayKey.key(s.startDate)] = "Вышел из дома рано, по набережной Иртыша."
        if let d = cal.date(byAdding: .day, value: 4, to: s.startDate) { s.dayNotes[DayKey.key(d)] = "Длинная прогулка после работы." }
        state = s
        suppressNotificationsOnce = true
        evaluateAndNotify()
        persist()
    }
    #endif

    func setting(for source: HealthSource) -> SourceSetting {
        state?.sourceSettings[source.id] ?? SourceSetting()
    }

    func updateSetting(for source: HealthSource, _ change: (inout SourceSetting) -> Void) {
        guard var current = state else { return }
        var setting = current.sourceSettings[source.id] ?? SourceSetting()
        change(&setting)
        current.sourceSettings[source.id] = setting
        state = current
        persist()
        Task { await syncSteps() }
    }

    // MARK: - Производные величины

    /// Километры за день: расстояние из «Здоровья», а если его за этот день нет — шаги × длина шага.
    /// Отладочные шаги всегда добавляются через длину шага.
    private static func walkedKm(on key: String, in s: GameState) -> Double { Journal.walkedKm(on: key, in: s) }

    /// Километры текущего пути без ограничения длиной маршрута: шаги с дня старта (без засчитанных прежнему пути) и полкилометра в день.
    private func rawKm(_ s: GameState) -> Double {
        let startKey = DayKey.key(s.startDate)
        let keys = Set(s.healthSteps.keys).union(s.healthDistanceKm.keys).union(s.debugSteps.keys).filter { $0 >= startKey }
        let walked = keys.reduce(0.0) { sum, key in
            sum + max(0, Self.walkedKm(on: key, in: s) - (key == startKey ? s.startBaselineKm : 0))
        }
        return walked + Double(daysElapsed(s)) * Self.passiveKmPerDay
    }

    /// Есть ли за сегодня данные о расстоянии из «Здоровья».
    var usesHealthDistance: Bool {
        guard let s = state else { return false }
        return (s.healthDistanceKm[DayKey.key(now)] ?? 0) > 0
    }

    private func daysElapsed(_ s: GameState) -> Int {
        let today = Calendar.current.startOfDay(for: now)
        return max(0, Calendar.current.dateComponents([.day], from: s.startDate, to: today).day ?? 0)
    }

    var totalKm: Double {
        guard let s = state else { return 0 }
        return min(rawKm(s), route.totalKm)
    }

    var dayNumber: Int { (state.map(daysElapsed) ?? 0) + 1 }

    var stepsToday: Int {
        guard let s = state else { return 0 }
        let key = DayKey.key(now)
        return (s.healthSteps[key] ?? 0) + (s.debugSteps[key] ?? 0)
    }

    var kmToday: Double {
        guard let s = state else { return 0 }
        return Self.walkedKm(on: DayKey.key(now), in: s)
    }

    var reachedStops: [Stop] { route.stops.filter { $0.km <= totalKm } }
    var currentStop: Stop { reachedStops.last ?? route.stops[0] }
    var nextStop: Stop? { route.stops.first { $0.km > totalKm } }
    var kmToNextStop: Double { nextStop.map { $0.km - totalKm } ?? 0 }

    var segmentProgress: Double {
        guard let next = nextStop else { return 1 }
        let from = currentStop.km
        return (totalKm - from) / (next.km - from)
    }

    var isFinished: Bool { state?.finishedAt != nil }

    // MARK: - Дневник

    /// Люди, встреченные на пройденных стоянках.
    var metPeople: [Character] { reachedStops.compactMap(\.character) }

    /// Звери и растения пройденных стоянок без повторов.
    var seenFauna: [Fauna] {
        var seen: [Fauna] = []
        for f in reachedStops.flatMap(\.fauna) where !seen.contains(where: { $0.name == f.name }) { seen.append(f) }
        return seen
    }

    var completedEvents: [RouteEvent] {
        route.events.filter { if case .completed = status(of: $0) { return true } else { return false } }
    }

    func status(of event: RouteEvent) -> EventStatus? { state?.eventStatus[event.id] }

    var activeEvent: ActiveEvent? {
        guard let s = state else { return nil }
        for event in route.events {
            if case let .active(startedAt, startKm) = s.eventStatus[event.id] {
                let deadline = startedAt.addingTimeInterval(Double(event.days) * 86_400)
                let secondsLeft = deadline.timeIntervalSince(now)
                return ActiveEvent(
                    event: event,
                    startedAt: startedAt,
                    startKm: startKm,
                    coveredKm: max(0, rawKm(s) - startKm),
                    daysLeft: max(0, Int((secondsLeft / 86_400).rounded(.up)))
                )
            }
        }
        return nil
    }

    /// Стоянка, к которой идёт путник; после финиша — последняя.
    var targetStop: Stop { nextStop ?? currentStop }

    var sceneTerrain: Terrain { targetStop.terrain }
    var regionName: String { targetStop.region }

    var trailNote: String {
        let notes = targetStop.trailNotes
        guard !notes.isEmpty else { return "" }
        return notes[(dayNumber + reachedStops.count) % notes.count]
    }

    /// Погода активного испытания; реальная погода подмешивается на экране.
    var eventWeather: SceneWeather? { activeEvent?.event.weather }

    /// Кого путник встретил сегодня: выбирается детерминированно по дате из фауны ближайшей стоянки.
    var encounterOfTheDay: Fauna? {
        let pool = (nextStop ?? currentStop).fauna
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0
        return pool[day % pool.count]
    }

    // MARK: - Внутреннее

    private func evaluateAndNotify() {
        let before = state
        evaluate()
        guard var current = state else { return }
        let newKm = min(rawKm(current), route.totalKm)
        // Стоянки сравниваем не с прошлым состоянием (шаги в него уже записаны), а с километражем последнего уведомления.
        let oldKm = current.lastNotifiedKm ?? newKm
        current.lastNotifiedKm = newKm
        state = current
        if suppressNotificationsOnce {
            suppressNotificationsOnce = false
            return
        }
        notifyTransitions(from: before, to: current, oldKm: oldKm, newKm: newKm)
    }

    /// Сравнивает состояние до и после пересчёта и шлёт уведомления о том, что изменилось в пути.
    private func notifyTransitions(from old: GameState?, to new: GameState, oldKm: Double, newKm: Double) {
        guard let old else { return }

        let reached = route.stops.filter { $0.km > 0 && $0.km > oldKm && $0.km <= newKm }
        if reached.count == 1, let stop = reached.first {
            let body = stop.character.map { String(localized: "Здесь вас встречает \($0.name), \($0.role.lowercased()). \(stop.subtitle).") } ?? stop.subtitle
            notify("stop-\(stop.id)", String(localized: "Вы дошли до: \(stop.name)"), body)
        } else if reached.count > 1, let last = reached.last {
            notify("stop-\(last.id)", String(localized: "Пройдено стоянок: \(reached.count)"), String(localized: "Последняя: \(last.name). Загляните в дневник."))
        }

        for event in route.events {
            let was = old.eventStatus[event.id]
            let now = new.eventStatus[event.id]
            switch (was, now) {
            case (.none, .some(.active)):
                notify("event-\(event.id)-start", event.title, String(localized: "\(event.description) Нужно пройти \(Fmt.km(event.goalKm)) км за \(Fmt.days(event.days))."))
            case (.some(.active), .some(.completed)):
                notify("event-\(event.id)-done", String(localized: "\(event.title): испытание пройдено"), event.rewardText)
            case (.some(.active), .some(.failed)):
                notify("event-\(event.id)-fail", String(localized: "\(event.title) позади"), String(localized: "Не успели, но путник справился. Записи в дневнике не будет, дорога продолжается."))
            default:
                break
            }
        }

        if old.finishedAt == nil, new.finishedAt != nil {
            notify("finish", String(localized: "Путь пройден!"), route.outro)
        }
    }

    private func evaluate() {
        guard var s = state else { return }
        let km = rawKm(s)
        let now = self.now

        for event in route.events {
            switch s.eventStatus[event.id] {
            case .none:
                if km >= event.triggerKm, s.finishedAt == nil {
                    s.eventStatus[event.id] = .active(startedAt: now, startKm: km)
                }
            case let .active(startedAt, startKm):
                if km - startKm >= event.goalKm {
                    s.eventStatus[event.id] = .completed(at: now)
                } else if now.timeIntervalSince(startedAt) > Double(event.days) * 86_400 {
                    s.eventStatus[event.id] = .failed(at: now)
                }
            default:
                break
            }
        }

        if km >= route.totalKm, s.finishedAt == nil {
            s.finishedAt = now
        }
        state = s
    }

    private func persist() {
        if let s = state { store.save(s) }
        publishWidgetSnapshot()
    }

    /// Складывает срез прогресса в общий контейнер и просит систему обновить виджеты.
    private func publishWidgetSnapshot() {
        if let s = state {
            WidgetSnapshot(
                aulName: s.heroName,
                routeTitle: route.title,
                dayNumber: dayNumber,
                kmToday: kmToday,
                kmTotal: totalKm,
                routeTotalKm: route.totalKm,
                stepsToday: stepsToday,
                nextStopName: nextStop?.name,
                kmToNextStop: kmToNextStop,
                regionName: regionName,
                isFinished: isFinished,
                updatedAt: now
            ).save()
        } else {
            WidgetSnapshot.clear()
        }
        if !isolated { WidgetCenter.shared.reloadAllTimelines() }
    }
}
