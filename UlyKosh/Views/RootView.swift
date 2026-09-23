import SwiftUI

struct RootView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if engine.isLoading {
                ProgressView()
            } else if engine.state == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .tint(Color.terracotta)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await engine.syncSteps() }
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Дорога", systemImage: "figure.walk") }
            RouteView()
                .tabItem { Label("Маршрут", systemImage: "map") }
            AulView()
                .tabItem { Label("Аул", systemImage: "tent") }
            SettingsView()
                .tabItem { Label("Ещё", systemImage: "ellipsis.circle") }
        }
    }
}
