import SwiftUI

struct HomeView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    private var weather: WeatherStore { WeatherStore.shared }

    /// Испытание важнее реальной погоды: буран в сюжете виден, даже если за окном солнце.
    private var atmosphere: Atmosphere {
        if let event = engine.eventWeather, weather.debugCondition == nil { return Atmosphere(event: event) }
        return weather.atmosphere ?? .fair
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    SceneView(terrain: engine.sceneTerrain, atmosphere: atmosphere)
                        .frame(height: geo.size.height * 0.52)
                        .id(engine.sceneTerrain)
                        .transition(.opacity)

                    VStack(spacing: 6) {
                        Text("День \(engine.dayNumber)")
                            .font(.display(20, weight: .regular))
                            .foregroundStyle(Color.parchment.opacity(0.85))
                            .padding(.top, 22)
                        Text("\(Date.now.formatted(.dateTime.day().month(.wide))) · \(Season.current().title)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ash)
                        WeatherLine()
                            .padding(.top, 2)

                        Text(Fmt.km(engine.totalKm))
                            .font(.display(66))
                            .foregroundStyle(Color.gold)
                            .padding(.top, 2)
                            .contentTransition(.numericText(value: engine.totalKm))
                        Text("км")
                            .font(.display(14, weight: .regular))
                            .foregroundStyle(Color.gold)
                            .padding(.top, -10)

                        Text(engine.regionName)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ash)
                            .padding(.top, 14)
                        Text(engine.isFinished ? engine.route.outro : engine.trailNote)
                            .font(.system(size: 16))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.parchment)
                            .padding(.horizontal, 28)
                            .padding(.top, 2)

                        if engine.isFinished {
                            ChangeJourneyButton()
                                .padding(.top, 18)
                        }

                        if let active = engine.activeEvent {
                            EventStrip(active: active)
                                .padding(.horizontal, 24)
                                .padding(.top, 18)
                        }

                        HStack(spacing: 6) {
                            Text("\(engine.stepsToday.formatted()) шагов сегодня")
                            if let next = engine.nextStop {
                                Text("·")
                                Text("до \(next.name) \(Fmt.km(engine.kmToNextStop)) км")
                            } else {
                                Text("·")
                                Text("маршрут пройден")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ash)
                        .padding(.top, 22)
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                }
                .animation(.easeInOut(duration: 0.9), value: engine.sceneTerrain)
                .animation(.easeInOut(duration: 0.7), value: engine.totalKm)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await engine.syncSteps()
                weather.refreshIfNeeded()
            }
        }
        .background(Color.night.ignoresSafeArea())
        .onAppear { weather.refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { weather.refreshIfNeeded() } }
    }
}

/// Погода там, где сейчас пользователь, и обязательная подпись Apple Weather.
struct WeatherLine: View {
    private var weather: WeatherStore { WeatherStore.shared }

    var body: some View {
        Group {
            switch weather.status {
            case .ready:
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        if let symbol = weather.symbolName {
                            Image(systemName: symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.gold)
                        }
                        if let t = weather.temperatureText {
                            Text(t).foregroundStyle(Color.parchment)
                        }
                        if let condition = weather.shownCondition {
                            Text(condition.description.lowercased())
                        }
                        if let place = weather.placeName {
                            Text("· \(place)")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
                    if let legal = weather.attributionLegalURL {
                        Link(destination: legal) {
                            Text("\u{F8FF} Weather")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.ash.opacity(0.7))
                        }
                    }
                }
            case .needsPermission:
                Button {
                    weather.requestPermission()
                } label: {
                    Label("Показать погоду", systemImage: "cloud.sun")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.gold)
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
        }
    }
}

/// Активное испытание: одна строка и тонкая золотая полоска прогресса.
struct EventStrip: View {
    let active: ActiveEvent

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PictogramView(kind: active.event.icon, size: 20)
                Text(active.event.title)
                    .font(.display(17, weight: .regular))
                    .foregroundStyle(Color.gold)
                Spacer()
                Text(active.daysLeft == 0 ? "последний день" : "осталось \(Fmt.days(active.daysLeft))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ash)
            }
            ProgressView(value: active.progress)
                .tint(Color.gold)
                .scaleEffect(y: 0.6)
            Text("\(Fmt.km(active.coveredKm)) из \(Fmt.km(active.event.goalKm)) км · \(active.event.rewardText)")
                .font(.system(size: 12))
                .foregroundStyle(Color.ash)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panel()
    }
}
