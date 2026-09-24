import Foundation

enum EventStatus: Codable, Hashable {
    case active(startedAt: Date, startKm: Double)
    case completed(at: Date)
    case failed(at: Date)
}

/// Всё, что нужно сохранить между запусками. Километры не хранятся, а считаются из шагов.
struct GameState: Codable {
    var routeId: String
    var aulName: String
    var startDate: Date
    /// Запасной коэффициент: используется только для дней без данных о расстоянии и для отладочных шагов.
    var strideMeters: Double = 0.7
    /// Шаги по дням из HealthKit, ключ — "yyyy-MM-dd".
    var healthSteps: [String: Int] = [:]
    /// Пройденные километры по дням из HealthKit. Основной источник расстояния.
    var healthDistanceKm: [String: Double] = [:]
    /// Шаги, добавленные вручную в отладочном режиме.
    var debugSteps: [String: Int] = [:]
    var eventStatus: [String: EventStatus] = [:]
    var herdBonus: HerdDelta = .zero
    var finishedAt: Date?
    /// HealthKit не сообщает статус чтения, поэтому запоминаем сами, что диалог уже показывали.
    var healthRequested: Bool = false

    init(routeId: String, aulName: String, startDate: Date) {
        self.routeId = routeId
        self.aulName = aulName
        self.startDate = startDate
    }

    // Терпимое декодирование: новые поля с дефолтами не должны ломать старые сохранения.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routeId = try c.decode(String.self, forKey: .routeId)
        aulName = try c.decode(String.self, forKey: .aulName)
        startDate = try c.decode(Date.self, forKey: .startDate)
        strideMeters = try c.decodeIfPresent(Double.self, forKey: .strideMeters) ?? 0.7
        healthSteps = try c.decodeIfPresent([String: Int].self, forKey: .healthSteps) ?? [:]
        healthDistanceKm = try c.decodeIfPresent([String: Double].self, forKey: .healthDistanceKm) ?? [:]
        debugSteps = try c.decodeIfPresent([String: Int].self, forKey: .debugSteps) ?? [:]
        eventStatus = try c.decodeIfPresent([String: EventStatus].self, forKey: .eventStatus) ?? [:]
        herdBonus = try c.decodeIfPresent(HerdDelta.self, forKey: .herdBonus) ?? .zero
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        healthRequested = try c.decodeIfPresent(Bool.self, forKey: .healthRequested) ?? false
    }
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = .current
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { formatter.string(from: date) }
}
