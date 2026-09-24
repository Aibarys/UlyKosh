import SwiftUI

struct OnboardingView: View {
    @Environment(GameEngine.self) private var engine
    @State private var aulName = ""
    @State private var isStarting = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    SceneView(terrain: engine.route.stops.first?.terrain ?? .river, phase: .dawn, showCaravan: true)
                        .frame(height: geo.size.height * 0.42)

                    VStack(spacing: 22) {
                        VStack(spacing: 6) {
                            Text("Ұлы Көш")
                                .font(.display(44, weight: .regular))
                                .foregroundStyle(Color.gold)
                            Text("Великое Кочевье")
                                .font(.system(size: 15))
                                .kerning(1)
                                .foregroundStyle(Color.ash)
                        }
                        .padding(.top, 28)

                        Text(engine.route.title)
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.gold.opacity(0.85))
                        Text(engine.route.intro)
                            .font(.system(size: 15))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.parchment)
                            .lineSpacing(3)

                        VStack(alignment: .leading, spacing: 12) {
                            featureRow("figure.walk", "Ваши шаги превращаются в километры пути")
                            featureRow("person.2", "На стоянках к аулу присоединяются люди")
                            featureRow("leaf", "Стадо растёт с каждым километром")
                            featureRow("wind.snow", "Буран и половодье проверят аул на прочность")
                        }
                        .panel()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Как назвать аул")
                            TextField("", text: $aulName, prompt: Text("Например, аул Жақыпа").foregroundStyle(Color.ash))
                                .foregroundStyle(Color.parchment)
                                .padding(12)
                                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.hairline))
                                .submitLabel(.done)
                        }

                        Button {
                            isStarting = true
                            Task {
                                await engine.startJourney(aulName: aulName)
                                isStarting = false
                            }
                        } label: {
                            Text(isStarting ? "Собираем юрты…" : "Начать кочевье")
                                .font(.display(19, weight: .medium))
                                .foregroundStyle(Color.night)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isStarting)

                        Text("Приложение попросит доступ к шагам в «Здоровье» и разрешение на уведомления, чтобы сообщать о стоянках и испытаниях. Данные остаются на устройстве.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ash)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.night.ignoresSafeArea())
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.gold)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.parchment)
        }
    }
}
