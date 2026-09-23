import Foundation
import HealthKit

/// Читает шаги по дням из HealthKit.
final class HealthKitStepSource {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

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
