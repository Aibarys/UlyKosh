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
    /// Аул идёт всегда, даже если хозяин сегодня не ходил: чуть-чуть, чтобы не было чувства вины.
    static let passiveKmPerDay = 0.5

    enum HealthStatus { case unknown, unavailable, requested }

    private(set) var state: GameState?
    private(set) var isLoading = true
    private(set) var healthStatus: HealthStatus = .unknown
    private(set) var lastSync: Date?
    var lastError: String?

    private let store = StateStore()
    private let health = HealthKitStepSource()
    private let notifications = NotificationService.shared

    /// Маршрут текущего кочевья; до старта — тот, что подходит по сезону.
    var route: Route {
        if let id = state?.routeId, let r = Routes.byId(id) { return r }
        return Routes.forStart()
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
        guard state != nil, health.isAvailable else { return }
        Task { await health.enableBackgroundDelivery() }
        health.startObserving { [weak self] in
            await self?.backgroundSync()
        }
    }

    private func backgroundSync() async {
        await load()
        await syncSteps()
    }

    func startJourney(aulName: String) async {
        let name = aulName.trimmingCharacters(in: .whitespacesAndNewlines)
        state = GameState(
            routeId: Routes.forStart().id,
            aulName: name.isEmpty ? String(localized: "Аул Ұлы Көш") : name,
            startDate: Calendar.current.startOfDay(for: .now)
        )
        persist()
        suppressNotificationsOnce = true
        await requestHealthAccess()
        await notifications.requestAuthorization()
        startObservingIfPossible()
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
        if health.isAvailable {
            // Шаги и расстояние читаем независимо: отказ по одному типу не должен ломать другой.
            async let stepsResult: Result<[Date: Int], Error> = {
                do { return .success(try await health.stepsPerDay(from: snapshot.startDate, to: .now)) } catch { return .failure(error) }
            }()
            async let distanceResult: Result<[Date: Double], Error> = {
                do { return .success(try await health.distanceKmPerDay(from: snapshot.startDate, to: .now)) } catch { return .failure(error) }
            }()
            let (steps, distance) = await (stepsResult, distanceResult)
            // Пока ждали HealthKit, состояние могло измениться, поэтому перечитываем.
            guard var current = state else { return }
            if case let .success(perDay) = steps {
                for (day, n) in perDay { current.healthSteps[DayKey.key(day)] = n }
            }
            if case let .success(perDay) = distance {
                for (day, km) in perDay { current.healthDistanceKm[DayKey.key(day)] = km }
            }
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
        guard !trimmed.isEmpty, state?.aulName != trimmed else { return }
        state?.aulName = trimmed
        persist()
    }

    func setStride(_ meters: Double) {
        state?.strideMeters = meters
        evaluateAndNotify()
        persist()
    }

    func addDebugSteps(_ steps: Int) {
        guard var current = state else { return }
        current.debugSteps[DayKey.key(.now), default: 0] += steps
        state = current
        evaluateAndNotify()
        persist()
    }

    // MARK: - Производные величины

    /// Километры за день: расстояние из «Здоровья», а если его за этот день нет — шаги × длина шага.
    /// Отладочные шаги всегда добавляются через длину шага.
    private static func walkedKm(on key: String, in s: GameState) -> Double {
        let health: Double
        if let km = s.healthDistanceKm[key], km > 0 {
            health = km
        } else {
            health = Double(s.healthSteps[key] ?? 0) * s.strideMeters / 1000
        }
        return health + Double(s.debugSteps[key] ?? 0) * s.strideMeters / 1000
    }

    private func rawKm(_ s: GameState) -> Double {
        let keys = Set(s.healthSteps.keys).union(s.healthDistanceKm.keys).union(s.debugSteps.keys)
        let walked = keys.reduce(0.0) { $0 + Self.walkedKm(on: $1, in: s) }
        return walked + Double(daysElapsed(s)) * Self.passiveKmPerDay
    }

    /// Есть ли за сегодня данные о расстоянии из «Здоровья».
    var usesHealthDistance: Bool {
        guard let s = state else { return false }
        return (s.healthDistanceKm[DayKey.key(.now)] ?? 0) > 0
    }

    private func daysElapsed(_ s: GameState) -> Int {
        let today = Calendar.current.startOfDay(for: .now)
        return max(0, Calendar.current.dateComponents([.day], from: s.startDate, to: today).day ?? 0)
    }

    var totalKm: Double {
        guard let s = state else { return 0 }
        return min(rawKm(s), route.totalKm)
    }

    var dayNumber: Int { (state.map(daysElapsed) ?? 0) + 1 }

    var stepsToday: Int {
        guard let s = state else { return 0 }
        let key = DayKey.key(.now)
        return (s.healthSteps[key] ?? 0) + (s.debugSteps[key] ?? 0)
    }

    var kmToday: Double {
        guard let s = state else { return 0 }
        return Self.walkedKm(on: DayKey.key(.now), in: s)
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

    var joinedCharacters: [Character] { reachedStops.compactMap(\.character) }

    var herd: Herd {
        let km = totalKm
        let bonus = state?.herdBonus ?? .zero
        return Herd(
            sheep: 120 + Int(km * 0.8) + bonus.sheep,
            horses: 24 + Int(km / 5) + bonus.horses,
            camels: 6 + Int(km / 40) + bonus.camels
        )
    }

    func status(of event: RouteEvent) -> EventStatus? { state?.eventStatus[event.id] }

    var activeEvent: ActiveEvent? {
        guard let s = state else { return nil }
        for event in route.events {
            if case let .active(startedAt, startKm) = s.eventStatus[event.id] {
                let deadline = startedAt.addingTimeInterval(Double(event.days) * 86_400)
                let secondsLeft = deadline.timeIntervalSince(.now)
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

    /// Стоянка, к которой идёт аул; после финиша — жайляу.
    var targetStop: Stop { nextStop ?? currentStop }

    var sceneTerrain: Terrain { targetStop.terrain }
    var regionName: String { targetStop.region }

    var trailNote: String {
        let notes = targetStop.trailNotes
        guard !notes.isEmpty else { return "" }
        return notes[(dayNumber + reachedStops.count) % notes.count]
    }

    var sceneWeather: SceneWeather { activeEvent?.event.weather ?? .clear }

    /// Кого аул встретил сегодня: выбирается детерминированно по дате из фауны ближайшей стоянки.
    var encounterOfTheDay: Fauna? {
        let pool = (nextStop ?? currentStop).fauna
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return pool[day % pool.count]
    }

    // MARK: - Внутреннее

    private func evaluateAndNotify() {
        let before = state
        evaluate()
        if suppressNotificationsOnce {
            suppressNotificationsOnce = false
            return
        }
        notifyTransitions(from: before, to: state)
    }

    /// Сравнивает состояние до и после пересчёта и шлёт уведомления о том, что изменилось в пути.
    private func notifyTransitions(from old: GameState?, to new: GameState?) {
        guard let old, let new else { return }
        let oldKm = min(rawKm(old), route.totalKm)
        let newKm = min(rawKm(new), route.totalKm)

        let reached = route.stops.filter { $0.km > 0 && $0.km > oldKm && $0.km <= newKm }
        if reached.count == 1, let stop = reached.first {
            let body = stop.character.map { String(localized: "\($0.role) \($0.name) присоединяется к аулу. \(stop.subtitle).") } ?? stop.subtitle
            notifications.post(id: "stop-\(stop.id)", title: String(localized: "Аул дошёл до стоянки \(stop.name)"), body: body)
        } else if reached.count > 1, let last = reached.last {
            notifications.post(id: "stop-\(last.id)", title: String(localized: "Аул прошёл \(reached.count) стоянки"), body: String(localized: "Последняя: \(last.name). Загляните в маршрут."))
        }

        for event in route.events {
            let was = old.eventStatus[event.id]
            let now = new.eventStatus[event.id]
            switch (was, now) {
            case (.none, .some(.active)):
                notifications.post(id: "event-\(event.id)-start", title: event.title,
                                   body: String(localized: "\(event.description) Нужно пройти \(Fmt.km(event.goalKm)) км за \(Fmt.days(event.days))."))
            case (.some(.active), .some(.completed)):
                notifications.post(id: "event-\(event.id)-done", title: String(localized: "\(event.title): аул справился"), body: event.rewardText)
            case (.some(.active), .some(.failed)):
                notifications.post(id: "event-\(event.id)-fail", title: String(localized: "\(event.title) позади"),
                                   body: String(localized: "Не успели, но аул справился. Награды не будет, дорога продолжается."))
            default:
                break
            }
        }

        if old.finishedAt == nil, new.finishedAt != nil {
            notifications.post(id: "finish", title: String(localized: "Кочевье окончено!"), body: route.outro)
        }
    }

    private func evaluate() {
        guard var s = state else { return }
        let km = rawKm(s)
        let now = Date.now

        for event in route.events {
            switch s.eventStatus[event.id] {
            case .none:
                if km >= event.triggerKm, s.finishedAt == nil {
                    s.eventStatus[event.id] = .active(startedAt: now, startKm: km)
                }
            case let .active(startedAt, startKm):
                if km - startKm >= event.goalKm {
                    s.eventStatus[event.id] = .completed(at: now)
                    s.herdBonus = s.herdBonus + event.reward
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
                aulName: s.aulName,
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
                updatedAt: .now
            ).save()
        } else {
            WidgetSnapshot.clear()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
