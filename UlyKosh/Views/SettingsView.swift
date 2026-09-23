import SwiftUI

struct SettingsView: View {
    @Environment(GameEngine.self) private var engine
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
                            Text(String(format: "%.2f м", stride)).foregroundStyle(.secondary)
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
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }

                #if DEBUG
                Section("Отладка") {
                    Button("Добавить 1 000 шагов сегодня") { engine.addDebugSteps(1_000) }
                    Button("Добавить 10 000 шагов сегодня") { engine.addDebugSteps(10_000) }
                    Button("Добавить 50 000 шагов сегодня") { engine.addDebugSteps(50_000) }
                }
                #endif

                Section {
                    Button("Сбросить кочевье", role: .destructive) { showResetConfirm = true }
                } footer: {
                    Text("Прогресс, стадо и события будут удалены. Шаги в «Здоровье» не затрагиваются.")
                }

                Section("О приложении") {
                    LabeledContent("Ұлы Көш", value: "MVP 0.1")
                    Text("Аул проходит \(Fmt.km(GameEngine.passiveKmPerDay)) км в день сам по себе, остальное зависит от ваших шагов.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.sand.ignoresSafeArea())
            .navigationTitle("Ещё")
            .onAppear {
                aulName = engine.state?.aulName ?? ""
                stride = engine.state?.strideMeters ?? 0.7
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
