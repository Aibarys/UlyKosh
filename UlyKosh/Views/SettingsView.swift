import SwiftUI

struct SettingsView: View {
    @Environment(GameEngine.self) private var engine
    private var notifications: NotificationService { NotificationService.shared }
    @State private var aulName = ""
    @State private var stride = 0.7
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Аул") {
                    TextField("Название аула", text: $aulName)
                        .onSubmit { engine.rename(aulName) }
                }

                Section("Шаги и расстояние") {
                    LabeledContent("Источник", value: healthText)
                    LabeledContent("Расстояние", value: engine.usesHealthDistance ? String(localized: "из «Здоровья»") : String(localized: "по шагам"))
                    if let sync = engine.lastSync {
                        LabeledContent("Синхронизация", value: sync.formatted(date: .omitted, time: .shortened))
                    }
                    Button("Запросить доступ к «Здоровью»") {
                        Task { await engine.requestHealthAccess() }
                    }
                    Button("Обновить шаги") {
                        Task { await engine.syncSteps() }
                    }
                    NavigationLink("Источники шагов") { SourcesView() }
                    if let error = engine.lastError {
                        Text(error).font(.caption).foregroundStyle(Color.ash)
                    }
                }

                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        LabeledContent("Язык приложения", value: Locale.current.language.languageCode?.identifier == "kk" ? "Қазақша" : "Русский")
                    }
                } footer: {
                    Text("Язык меняется в настройках iOS. Доступны русский и казахский.")
                }

                Section("Уведомления") {
                    LabeledContent("Статус", value: notifications.authorized ? String(localized: "Разрешены") : String(localized: "Не разрешены"))
                    Button("Разрешить уведомления") {
                        Task { await notifications.requestAuthorization() }
                    }
                    Text("Аул сообщит, когда дойдёт до стоянки, когда начнётся буран или половодье и когда испытание пройдено.")
                        .font(.footnote)
                        .foregroundStyle(Color.ash)
                }

                if BuildEnvironment.showsDebugTools {
                Section("Отладка") {
                    Button("Тестовое уведомление через 5 с") {
                        notifications.post(id: "test", title: "Аул дошёл до стоянки Отырар", body: "Ақын Сәкен присоединяется к аулу.", delay: 5)
                    }
                    Button("Добавить 1 000 шагов сегодня") { engine.addDebugSteps(1_000) }
                    Button("Добавить 10 000 шагов сегодня") { engine.addDebugSteps(10_000) }
                    Button("Добавить 50 000 шагов сегодня") { engine.addDebugSteps(50_000) }
                    NavigationLink("Все пиктограммы") { PictogramSheetView() }
                    NavigationLink("Сцены по сезонам") { SeasonSheetView() }
                    NavigationLink("Сцены по местности") { TerrainSheetView() }
                    NavigationLink("Виджет") { WidgetPreviewSheet() }
                    Menu("Начать другой маршрут") {
                        ForEach(Routes.all) { route in
                            Button("\(route.title) · \(route.season)") {
                                let name = engine.state?.aulName ?? ""
                                engine.resetJourney()
                                Task { await engine.startJourney(aulName: name, routeId: route.id) }
                            }
                        }
                    }
                }
                }

                Section {
                    Button("Сбросить кочевье", role: .destructive) { showResetConfirm = true }
                } footer: {
                    Text("Прогресс, стадо и события будут удалены. Шаги в «Здоровье» не затрагиваются.")
                }

                Section("Длина шага") {
                    Stepper(value: $stride, in: 0.5...0.9, step: 0.05) {
                        HStack {
                            Text("Запасной коэффициент")
                            Spacer()
                            Text(String(format: "%.2f м", stride)).foregroundStyle(Color.ash)
                        }
                    }
                    .onChange(of: stride) { _, value in engine.setStride(value) }
                    Text("Используется только для дней, за которые в «Здоровье» нет данных о расстоянии.")
                        .font(.footnote)
                        .foregroundStyle(Color.ash)
                }

                Section("О приложении") {
                    LabeledContent("Ұлы Көш", value: Self.versionString)
                    if BuildEnvironment.current != .appStore {
                        LabeledContent("Сборка", value: BuildEnvironment.current.title)
                    }
                    Text("Аул проходит \(Fmt.km(GameEngine.passiveKmPerDay)) км в день сам по себе, остальное зависит от ваших шагов.")
                        .font(.footnote)
                        .foregroundStyle(Color.ash)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.night.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenHeader(title: String(localized: "Ещё"))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    .background(Color.night)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                aulName = engine.state?.aulName ?? ""
                stride = engine.state?.strideMeters ?? 0.7
                Task { await notifications.refreshStatus() }
            }
            .confirmationDialog("Сбросить кочевье?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { engine.resetJourney() }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var healthText: String {
        switch engine.healthStatus {
        case .unavailable: return String(localized: "Здоровье недоступно")
        case .requested: return String(localized: "Здоровье")
        case .unknown: return String(localized: "Доступ не запрошен")
        }
    }
}


/// Какие приложения и устройства учитывать при подсчёте километров.
struct SourcesView: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        Form {
            if engine.healthSources.isEmpty {
                Text("В «Здоровье» пока нет данных о шагах. Источники появятся после первой прогулки.")
                    .foregroundStyle(Color.ash)
            }
            ForEach(engine.healthSources) { source in
                let setting = engine.setting(for: source)
                Section {
                    Toggle(isOn: Binding(
                        get: { setting.enabled },
                        set: { value in engine.updateSetting(for: source) { $0.enabled = value } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                            Text("сегодня \((engine.stepsTodayBySource[source.id] ?? 0).formatted()) шагов")
                                .font(.footnote)
                                .foregroundStyle(Color.ash)
                        }
                    }
                    if setting.enabled {
                        Toggle(isOn: Binding(
                            get: { setting.nightFilter },
                            set: { value in engine.updateSetting(for: source) { $0.nightFilter = value } }
                        )) {
                            Text("Ночной фильтр, 23:00–06:00")
                        }
                    }
                }
            }
            Section {
                Text("Если несколько устройств считали одну прогулку, за каждый час берётся наибольшее значение. Расстояние берётся от устройств, которые его пишут, например iPhone и Apple Watch. Шаги браслета, которых нет у телефона, например на беговой дорожке, переводятся в километры по длине шага. Ночной фильтр отбрасывает шаги устройства с 23:00 до 06:00.")
                    .font(.footnote)
                    .foregroundStyle(Color.ash)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.night.ignoresSafeArea())
        .navigationTitle("Источники шагов")
        .navigationBarTitleDisplayMode(.inline)
        .task { await engine.syncSteps() }
    }
}
