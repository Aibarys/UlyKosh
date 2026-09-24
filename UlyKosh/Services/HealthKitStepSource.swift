import Foundation
import HealthKit

/// Читает шаги по дням из HealthKit.
final class HealthKitStepSource {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private var observerQuery: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Просим систему будить приложение, когда в «Здоровье» появляются новые шаги. Для шагов минимум раз в час.
    func enableBackgroundDelivery() async {
        guard isAvailable else { return }
        try? await store.enableBackgroundDelivery(for: stepType, frequency: .hourly)
    }

    /// Наблюдатель срабатывает и в фоне, и когда приложение открыто. `handler` должен закончить работу до вызова completion.
    func startObserving(_ handler: @escaping @Sendable () async -> Void) {
        guard isAvailable, observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task {
                await handler()
                completion()
            }
        }
        observerQuery = query
        store.execute(query)
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [stepType])
    }

    /// Сумма шагов за каждый календарный день от `start` до `end`.
    func stepsPerDay(from start: Date, to end: Date) async throws -> [Date: Int] {
        guard isAvailable else { return [:] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
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
                var result: [Date: Int] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { stats, _ in
                    let value = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    result[stats.startDate] = Int(value.rounded())
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
