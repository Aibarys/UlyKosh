import Foundation
import HealthKit

struct HealthSource: Identifiable, Hashable {
    let id: String
    let name: String
}

/// Читает шаги и пройденное расстояние по часам и источникам из HealthKit.
final class HealthKitStepSource {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private var observerQueries: [HKObserverQuery] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [stepType, distanceType])
    }

    /// Просим систему будить приложение, когда появляются новые данные. Для шагов и дистанции минимум раз в час.
    func enableBackgroundDelivery() async {
        guard isAvailable else { return }
        try? await store.enableBackgroundDelivery(for: stepType, frequency: .hourly)
        try? await store.enableBackgroundDelivery(for: distanceType, frequency: .hourly)
    }

    /// Наблюдатель срабатывает и в фоне, и когда приложение открыто. `handler` должен закончить работу до вызова completion.
    func startObserving(_ handler: @escaping @Sendable () async -> Void) {
        guard isAvailable, observerQueries.isEmpty else { return }
        for type in [stepType, distanceType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }
                Task {
                    await handler()
                    completion()
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    /// Шаги по часам и источникам: час → (идентификатор источника → шаги).
    func hourlyStepsBySource(from start: Date, to end: Date) async throws -> [Date: [String: Double]] {
        try await hourlySumsBySource(of: stepType, unit: .count(), from: start, to: end)
    }

    /// Километры по часам и источникам.
    func hourlyDistanceKmBySource(from start: Date, to end: Date) async throws -> [Date: [String: Double]] {
        try await hourlySumsBySource(of: distanceType, unit: .meterUnit(with: .kilo), from: start, to: end)
    }

    /// Все источники, которые когда-либо писали шаги или расстояние.
    func sources() async throws -> [HealthSource] {
        guard isAvailable else { return [] }
        var found: [String: HealthSource] = [:]
        for type in [stepType, distanceType] {
            let set: Set<HKSource> = try await withCheckedThrowingContinuation { continuation in
                let query = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: sources ?? []) }
                }
                store.execute(query)
            }
            for source in set {
                found[source.bundleIdentifier] = HealthSource(id: source.bundleIdentifier, name: source.name)
            }
        }
        return found.values.sorted { $0.name < $1.name }
    }

    private func hourlySumsBySource(of type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> [Date: [String: Double]] {
        guard isAvailable else { return [:] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource],
                anchorDate: anchor,
                intervalComponents: DateComponents(hour: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var result: [Date: [String: Double]] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    guard let sources = stats.sources, !sources.isEmpty else { return }
                    var bySource: [String: Double] = [:]
                    for source in sources {
                        let value = stats.sumQuantity(for: source)?.doubleValue(for: unit) ?? 0
                        if value > 0 { bySource[source.bundleIdentifier] = value }
                    }
                    if !bySource.isEmpty { result[stats.startDate] = bySource }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
