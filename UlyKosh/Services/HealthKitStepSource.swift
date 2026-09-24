import Foundation
import HealthKit

/// Читает шаги и пройденное расстояние по дням из HealthKit.
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

    /// Сумма шагов за каждый календарный день от `start` до `end`.
    func stepsPerDay(from start: Date, to end: Date) async throws -> [Date: Int] {
        let sums = try await dailySums(of: stepType, unit: .count(), from: start, to: end)
        return sums.mapValues { Int($0.rounded()) }
    }

    /// Пройденные километры (ходьба и бег) за каждый календарный день.
    func distanceKmPerDay(from start: Date, to end: Date) async throws -> [Date: Double] {
        try await dailySums(of: distanceType, unit: .meterUnit(with: .kilo), from: start, to: end)
    }

    private func dailySums(of type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> [Date: Double] {
        guard isAvailable else { return [:] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    result[stats.startDate] = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
