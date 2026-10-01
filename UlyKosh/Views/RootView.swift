import SwiftUI

struct RootView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if engine.isLoading {
                ZStack {
                    Color.night.ignoresSafeArea()
                    ProgressView().tint(Color.gold)
                }
            } else if engine.state == nil {
                OnboardingView()
            } else if DebugLaunch.showsWeatherSheet {
                NavigationStack { WeatherSheetView() }
            } else if let (a, b) = DebugLaunch.routePreview {
                NavigationStack { RoutePickerView(onStart: { _ in }, from: a, to: b) }
            } else {
                MainTabView()
            }
        }
        .tint(Color.gold)
        .preferredColorScheme(.dark)
        .onChange(of: engine.isLoading) { _, loading in
            #if DEBUG
            if !loading, DebugLaunch.journalDemo { engine.seedJournalDemo() }
            if !loading, ProcessInfo.processInfo.arguments.contains("-finishDemo"), let s = engine.state {
                engine.addDebugSteps(Int((engine.route.totalKm - engine.totalKm + 1) * 1000 / s.strideMeters))
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await engine.syncSteps() }
            }
        }
    }
}

enum AppTab: CaseIterable {
    case road, route, aul, more

    var symbol: String {
        switch self {
        case .road: return "figure.walk"
        case .route: return "map"
        case .aul: return "book"
        case .more: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .road: return String(localized: "Дорога")
        case .route: return String(localized: "Маршрут")
        case .aul: return String(localized: "Дневник")
        case .more: return String(localized: "Ещё")
        }
    }
}

struct MainTabView: View {
    @Environment(GameEngine.self) private var engine
    @State private var tab: AppTab = DebugLaunch.startTab ?? .road

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .road: HomeView()
                case .route: RouteView()
                case .aul: JournalView()
                case .more: SettingsView()
                }
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBarView(selected: $tab)
        }
        .background(Color.night.ignoresSafeArea())
        .sheet(isPresented: Binding(
            get: { engine.isFinished && engine.state?.finishSeen == false },
            set: { if !$0 { engine.markFinishSeen() } }
        )) {
            FinishSummaryView()
        }
    }
}

/// Тонкие золотые иконки без подписей на чёрной полосе.
struct TabBarView: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { selected = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(selected == tab ? Color.gold : Color.ash.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 12)
        .background(Color.night.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 0.5) }
    }
}


/// Аргументы запуска для отладки в симуляторе:
/// `-weatherSheet` открывает лист всех погод, `-weather rain` показывает состояние на главном.
enum DebugLaunch {
    static var showsWeatherSheet: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-weatherSheet")
        #else
        return false
        #endif
    }

    /// `-route Pavlodar Beskaragay`: открыть предпросмотр пути между пунктами (поиск по латинице).
    static var routePreview: (Place, Place)? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-route"), i + 2 < args.count,
              let a = PlaceStore.shared.search(args[i + 1]).first,
              let b = PlaceStore.shared.search(args[i + 2]).first(where: { place in
                  args.count > i + 3 ? place.regionName.lowercased().contains(args[i + 3].lowercased()) : true
              }) else { return nil }
        return (a, b)
        #else
        return nil
        #endif
    }

    /// `-tab journal`: открыть приложение сразу на вкладке.
    static var startTab: AppTab? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "route": return .route
        case "journal": return .aul
        case "more": return .more
        default: return .road
        }
        #else
        return nil
        #endif
    }

    /// `-journalDemo`: заполнить дневник примером за 10 дней.
    static var journalDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-journalDemo")
        #else
        return false
        #endif
    }

    static var condition: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-weather"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }
}
