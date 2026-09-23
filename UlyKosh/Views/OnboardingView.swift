import SwiftUI

struct OnboardingView: View {
    @Environment(GameEngine.self) private var engine
    @State private var aulName = ""
    @State private var isStarting = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.sky, .sand, .sand], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)
                    Text("🏕️")
                        .font(.system(size: 88))
                    VStack(spacing: 6) {
                        Text("Ұлы Көш")
                            .font(.system(size: 42, weight: .bold, design: .serif))
                        Text("Великое Кочевье")
                            .font(.title3)
                            .foregroundStyle(Color.inkSoft)
                    }

                    Text(engine.route.intro)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Как это работает")
                            .font(.headline)
                        Label("Ваши шаги превращаются в километры пути", systemImage: "figure.walk")
                        Label("На стоянках к аулу присоединяются люди", systemImage: "person.2")
                        Label("Стадо растёт с каждым километром", systemImage: "leaf")
                        Label("Буран и половодье проверят аул на прочность", systemImage: "wind")
                    }
                    .font(.subheadline)
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Как назвать аул?")
                            .font(.headline)
                        TextField("Например, аул Жақыпа", text: $aulName)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                    }
                    .card()

                    Button {
                        isStarting = true
                        Task {
                            await engine.startJourney(aulName: aulName)
                            isStarting = false
                        }
                    } label: {
                        Text(isStarting ? "Собираем юрты…" : "Начать кочевье")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStarting)

                    Text("Приложение попросит доступ к шагам в «Здоровье». Данные остаются на устройстве.")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Color.ink)
    }
}
