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
                    Stepper(value: $stride, in: 0.5...0.9, step: 0.05) {
                        HStack {
                            Text("Длина шага")
                            Spacer()
                            Text(String(format: "%.2f м", stride)).foregroundStyle(Color.ash)
                        }
                    }
                    .onChange(of: stride) { _, value in engine.setStride(value) }
                }

                Section("Шаги") {
                    LabeledContent("Источник", value: healthText)
                    if let sync = engine.lastSync {
                        LabeledContent("Синхронизация", value: sync.formatted(date: .omitted, time: .shortened))
                    }
                    Button("Запросить доступ к «Здоровью»") {
                        Task { await engine.requestHealthAccess() }
                    }
                    Button("Обновить шаги") {
                        Task { await engine.syncSteps() }
                    }
                    if let error = engine.lastError {
                        Text(error).font(.caption).foregroundStyle(Color.ash)
                    }
                }

                Section("Уведомления") {
                    LabeledContent("Статус", value: notifications.authorized ? "Разрешены" : "Не разрешены")
                    Button("Разрешить уведомления") {
                        Task { await notifications.requestAuthorization() }
                    }
                    Text("Аул сообщит, когда дойдёт до стоянки, когда начнётся буран или половодье и когда испытание пройдено.")
                        .font(.footnote)
                        .foregroundStyle(Color.ash)
                }

                #if DEBUG
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
                }
                #endif

                Section {
                    Button("Сбросить кочевье", role: .destructive) { showResetConfirm = true }
                } footer: {
                    Text("Прогресс, стадо и события будут удалены. Шаги в «Здоровье» не затрагиваются.")
                }

                Section("О приложении") {
                    LabeledContent("Ұлы Көш", value: "MVP 0.2")
                    Text("Аул проходит \(Fmt.km(GameEngine.passiveKmPerDay)) км в день сам по себе, остальное зависит от ваших шагов.")
                        .font(.footnote)
                        .foregroundStyle(Color.ash)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.night.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenHeader(title: "Ещё")
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

    private var healthText: String {
        switch engine.healthStatus {
        case .unavailable: return "Здоровье недоступно"
        case .requested: return "Здоровье"
        case .unknown: return "Доступ не запрошен"
        }
    }
}
