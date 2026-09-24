import SwiftUI

@main
struct UlyKoshApp: App {
    @State private var engine: GameEngine

    init() {
        let engine = GameEngine()
        _engine = State(initialValue: engine)
        NotificationService.shared.configure()
        // Наблюдатель HealthKit должен регистрироваться при каждом запуске, в том числе когда система будит приложение в фоне.
        Task { await engine.bootstrap() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .task { await engine.bootstrap() }
        }
    }
}
