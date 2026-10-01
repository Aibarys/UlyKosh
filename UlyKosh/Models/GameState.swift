import Foundation

/// Как учитывать источник шагов из «Здоровья».
struct SourceSetting: Codable, Hashable {
    var enabled: Bool = true
    /// Отбрасывать шаги этого источника в тихие часы (23:00–06:00).
    var nightFilter: Bool = false
}

enum EventStatus: Codable, Hashable {
    case active(startedAt: Date, startKm: Double)
    case completed(at: Date)
    case failed(at: Date)
}

/// Погода дня для дневника.
struct WeatherNote: Codable, Hashable {
    var temperature: Double
    var condition: String
    var symbol: String
    var place: String?
}

/// Пройденный или оставленный путь в архиве. Шаги по дням хранятся общие, здесь только рамки пути.
struct JourneyRecord: Codable, Identifiable, Hashable {
    var id: String
    var routeId: String
    var customRoute: CustomRoute?
    /// Начало дня старта.
    var startDate: Date
    /// Километры дня старта, засчитанные предыдущему пути.
    var startBaselineKm: Double
    /// Когда путь закончился: дошли до конца или свернули.
    var endedAt: Date
    /// Сколько км пройдено по этому пути.
    var km: Double
    var finished: Bool
    var eventStatus: [String: EventStatus]
}

/// Всё, что нужно сохранить между запусками. Километры не хранятся, а считаются из шагов.
struct GameState: Codable {
    var routeId: String
    /// Имя путника. В файле лежит под старым ключом aulName, чтобы старые сохранения читались.
    var heroName: String
    var startDate: Date
    /// Запасной коэффициент: используется только для дней без данных о расстоянии и для отладочных шагов.
    var strideMeters: Double = 0.7
    /// Шаги по дням из HealthKit, ключ — "yyyy-MM-dd".
    var healthSteps: [String: Int] = [:]
    /// Километры по дням, рассчитанные из «Здоровья» с учётом источников. Основной источник расстояния.
    var healthDistanceKm: [String: Double] = [:]
    /// Настройки по источникам, ключ — bundle identifier источника.
    var sourceSettings: [String: SourceSetting] = [:]
    /// Шаги, добавленные вручную в отладочном режиме.
    var debugSteps: [String: Int] = [:]
    var eventStatus: [String: EventStatus] = [:]
    var finishedAt: Date?
    /// Свой маршрут из точки А в точку Б, если выбран.
    var customRoute: CustomRoute?
    /// HealthKit не сообщает статус чтения, поэтому запоминаем сами, что диалог уже показывали.
    var healthRequested: Bool = false
    /// Километраж, по которому уже отправлены уведомления о стоянках. nil — ещё не инициализирован.
    var lastNotifiedKm: Double?
    /// Первый день дневника: с него читаются шаги, сколько бы путей ни сменилось.
    var journalStart: Date
    /// Километры дня старта, которые засчитаны предыдущему пути (новый путь начинается с нуля).
    var startBaselineKm: Double = 0
    /// Итоги пройденного пути уже показаны.
    var finishSeen: Bool = false
    /// Прошлые пути, от старых к новым.
    var history: [JourneyRecord] = []
    /// Шаги по часам для дневника: день → 24 значения.
    var hourlySteps: [String: [Int]] = [:]
    /// Отладочные шаги по часам (хранятся отдельно, чтобы синхронизация со «Здоровьем» их не стирала).
    var debugHourlySteps: [String: [Int]] = [:]
    /// Погода, которую путник видел в этот день.
    var weatherLog: [String: WeatherNote] = [:]
    /// Заметки пользователя по дням.
    var dayNotes: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case routeId, heroName = "aulName", startDate, strideMeters, healthSteps, healthDistanceKm, sourceSettings,
             debugSteps, eventStatus, finishedAt, customRoute, healthRequested, lastNotifiedKm,
             hourlySteps, debugHourlySteps, weatherLog, dayNotes, journalStart, startBaselineKm, finishSeen, history
    }

    init(routeId: String, heroName: String, startDate: Date, customRoute: CustomRoute? = nil) {
        self.routeId = routeId
        self.heroName = heroName
        self.startDate = startDate
        self.journalStart = startDate
        self.customRoute = customRoute
    }

    // Терпимое декодирование: новые поля с дефолтами не должны ломать старые сохранения.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routeId = try c.decode(String.self, forKey: .routeId)
        heroName = try c.decode(String.self, forKey: .heroName)
        startDate = try c.decode(Date.self, forKey: .startDate)
        strideMeters = try c.decodeIfPresent(Double.self, forKey: .strideMeters) ?? 0.7
        healthSteps = try c.decodeIfPresent([String: Int].self, forKey: .healthSteps) ?? [:]
        healthDistanceKm = try c.decodeIfPresent([String: Double].self, forKey: .healthDistanceKm) ?? [:]
        sourceSettings = try c.decodeIfPresent([String: SourceSetting].self, forKey: .sourceSettings) ?? [:]
        debugSteps = try c.decodeIfPresent([String: Int].self, forKey: .debugSteps) ?? [:]
        eventStatus = try c.decodeIfPresent([String: EventStatus].self, forKey: .eventStatus) ?? [:]
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        customRoute = try c.decodeIfPresent(CustomRoute.self, forKey: .customRoute)
        healthRequested = try c.decodeIfPresent(Bool.self, forKey: .healthRequested) ?? false
        lastNotifiedKm = try c.decodeIfPresent(Double.self, forKey: .lastNotifiedKm)
        hourlySteps = try c.decodeIfPresent([String: [Int]].self, forKey: .hourlySteps) ?? [:]
        journalStart = try c.decodeIfPresent(Date.self, forKey: .journalStart) ?? startDate
        startBaselineKm = try c.decodeIfPresent(Double.self, forKey: .startBaselineKm) ?? 0
        finishSeen = try c.decodeIfPresent(Bool.self, forKey: .finishSeen) ?? false
        history = try c.decodeIfPresent([JourneyRecord].self, forKey: .history) ?? []
        debugHourlySteps = try c.decodeIfPresent([String: [Int]].self, forKey: .debugHourlySteps) ?? [:]
        weatherLog = try c.decodeIfPresent([String: WeatherNote].self, forKey: .weatherLog) ?? [:]
        dayNotes = try c.decodeIfPresent([String: String].self, forKey: .dayNotes) ?? [:]
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
