import Foundation
@testable import UlyKosh

/// Подменяемые часы для движка.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(days: Double = 0, hours: Double = 0) { now = now.addingTimeInterval(days * 86_400 + hours * 3_600) }
}

enum Fixtures {
    /// 15 апреля 2026, 10:00 — весна, стартует весенний маршрут.
    static let spring = date(2026, 4, 15, 10)
    /// 28 сентября 2026, 10:00 — осень.
    static let autumn = date(2026, 9, 28, 10)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ulykosh-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
struct Harness {
    let clock: TestClock
    let engine: GameEngine
    var notifications: [(id: String, title: String, body: String)] = []

    init(start: Date) async {
        clock = TestClock(start)
        let c = clock
        engine = GameEngine(storeDirectory: Fixtures.tempDirectory(), clock: { c.now })
        await engine.load()
        await engine.startJourney(heroName: "Тестовый путник")
    }

    /// Начинает записывать уведомления.
    mutating func recordNotifications() -> NotificationLog {
        let log = NotificationLog()
        engine.notify = { id, title, body in log.items.append((id, title, body)) }
        return log
    }

    /// Прибавляет километры через отладочные шаги (стандартная длина шага 0.7 м).
    func walk(km: Double) {
        engine.addDebugSteps(Int((km * 1000 / 0.7).rounded(.up)))
    }
}

final class NotificationLog: @unchecked Sendable {
    var items: [(id: String, title: String, body: String)] = []
    func ids() -> [String] { items.map(\.id) }
}
