import SwiftUI
import WeatherKit

/// Отладочный лист: все состояния погоды WeatherKit на одной сцене.
struct WeatherSheetView: View {
    @State private var phase: SkyPhase = .day
    @State private var terrain: Terrain = .steppe
    private var weather: WeatherStore { WeatherStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Время", selection: $phase) {
                    Text("Рассвет").tag(SkyPhase.dawn)
                    Text("День").tag(SkyPhase.day)
                    Text("Закат").tag(SkyPhase.dusk)
                    Text("Ночь").tag(SkyPhase.night)
                }
                .pickerStyle(.segmented)
                Picker("Местность", selection: $terrain) {
                    Text("Степь").tag(Terrain.steppe)
                    Text("Река").tag(Terrain.river)
                    Text("Горы").tag(Terrain.mountains)
                    Text("Город").tag(Terrain.town)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                    ForEach(Atmosphere.allConditions, id: \.self) { condition in
                        Button {
                            weather.debugCondition = condition
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                SceneView(terrain: terrain, phase: phase, season: .summer, atmosphere: Atmosphere(condition: condition))
                                    .frame(height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(weather.debugCondition == condition ? Color.gold : .clear, lineWidth: 2))
                                Text(condition.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.parchment)
                                Text(condition.rawValue)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color.ash)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if weather.debugCondition != nil {
                    Button("Вернуть реальную погоду") { weather.debugCondition = nil }
                        .foregroundStyle(Color.gold)
                }
                Text("Нажмите на сцену, чтобы показать эту погоду на главном экране.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ash)
            }
            .padding(16)
        }
        .background(Color.night.ignoresSafeArea())
        .navigationTitle("Погода на сцене")
        .navigationBarTitleDisplayMode(.inline)
    }
}
