import Foundation

/// Снимок прогресса для виджета. Приложение пишет его в общий контейнер, виджет только читает.
struct WidgetSnapshot: Codable {
    static let appGroup = "group.kz.ulykosh"

    var aulName: String
    var routeTitle: String
    var dayNumber: Int
    var kmToday: Double
    var kmTotal: Double
    var routeTotalKm: Double
    var stepsToday: Int
    var nextStopName: String?
    var kmToNextStop: Double
    var regionName: String
    var isFinished: Bool
    var updatedAt: Date

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static let placeholder = WidgetSnapshot(
        aulName: "Аул Ұлы Көш", routeTitle: "Сырдария → Ұлытау", dayNumber: 12,
        kmToday: 4.6, kmTotal: 87, routeTotalKm: 520, stepsToday: 6_580,
        nextStopName: "Перевал Қаратау", kmToNextStop: 23, regionName: "Предгорья Қаратау",
        isFinished: false, updatedAt: .now
    )
}
