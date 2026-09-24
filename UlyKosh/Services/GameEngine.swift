import Foundation
import Observation

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

    let route: Route = SpringRoute.route
    private let store = StateStore()
    private let health = HealthKitStepSource()

    // MARK: - Жизненный цикл

    func load() async {
        state = store.load()
        isLoading = false
        if !health.isAvailable {
            healthStatus = .unavailable
        } else if state?.healthRequested == true {
            healthStatus = .requested
        }
        if state != nil { await syncSteps() }
    }

    func startJourney(aulName: String) async {
        let name = aulName.trimmingCharacters(in: .whitespacesAndNewlines)
        state = GameState(
            routeId: route.id,
            aulName: name.isEmpty ? "Аул Ұлы Көш" : name,
            startDate: Calendar.current.startOfDay(for: .now)
        )
        persist()
        await requestHealthAccess()
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
            do {
                let perDay = try await health.stepsPerDay(from: snapshot.startDate, to: .now)
                // Пока ждали HealthKit, состояние могло измениться, поэтому перечитываем.
                guard var current = state else { return }
                for (day, steps) in perDay {
                    current.healthSteps[DayKey.key(day)] = steps
                }
                state = current
                lastSync = .now
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
        evaluate()
        persist()
    }

    func resetJourney() {
        state = nil
        store.clear()
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
        evaluate()
        persist()
    }

    func addDebugSteps(_ steps: Int) {
        guard var current = state else { return }
        current.debugSteps[DayKey.key(.now), default: 0] += steps
        state = current
        evaluate()
        persist()
    }

    // MARK: - Производные величины

    private func rawKm(_ s: GameState) -> Double {
        let steps = s.healthSteps.values.reduce(0, +) + s.debugSteps.values.reduce(0, +)
        let stepKm = Double(steps) * s.strideMeters / 1000
        return stepKm + Double(daysElapsed(s)) * Self.passiveKmPerDay
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

    var kmToday: Double { Double(stepsToday) * (state?.strideMeters ?? 0.7) / 1000 }

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

    var sceneWeather: SceneWeather {
        switch activeEvent?.event.id {
        case "buran": return .snow
        case "sandstorm": return .sand
        default: return .clear
        }
    }

    /// Кого аул встретил сегодня: выбирается детерминированно по дате из фауны ближайшей стоянки.
    var encounterOfTheDay: Fauna? {
        let pool = (nextStop ?? currentStop).fauna
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return pool[day % pool.count]
    }

    // MARK: - Внутреннее

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
    }
}
