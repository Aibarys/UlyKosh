import SwiftUI

@main
struct UlyKoshApp: App {
    @State private var engine = GameEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .task { await engine.load() }
        }
    }
}
