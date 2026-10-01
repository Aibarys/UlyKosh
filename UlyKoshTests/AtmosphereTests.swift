import Testing
import WeatherKit
@testable import UlyKosh

/// Каждое состояние WeatherKit получает свою, правдоподобную картинку.
struct AtmosphereTests {
    @Test("Все 34 состояния WeatherKit разложены на слои")
    func allConditionsCovered() {
        #expect(Atmosphere.allConditions.count == 34)
        #expect(Set(Atmosphere.allConditions.map(\.rawValue)).count == 34)
    }

    @Test("Осадки соответствуют состоянию")
    func precipitation() {
        #expect(Atmosphere(condition: .clear).precipitation == .none)
        #expect(Atmosphere(condition: .drizzle).precipitation == .drizzle)
        #expect(Atmosphere(condition: .heavyRain).precipitation == .heavyRain)
        #expect(Atmosphere(condition: .snow).isSnowy)
        #expect(Atmosphere(condition: .hail).precipitation == .hail)
        #expect(Atmosphere(condition: .freezingRain).glaze)
    }

    @Test("Гроза: молнии, и чем сильнее, тем темнее")
    func storms() {
        let isolated = Atmosphere(condition: .isolatedThunderstorms)
        let strong = Atmosphere(condition: .strongStorms)
        #expect(isolated.lightning > 0 && strong.lightning > isolated.lightning)
        #expect(strong.darkness > isolated.darkness)
        #expect(Atmosphere(condition: .rain).lightning == 0)
    }

    @Test("Облачность растёт от ясно к пасмурно, реальные данные учитываются")
    func cloudCover() {
        let order: [WeatherCondition] = [.clear, .mostlyClear, .partlyCloudy, .mostlyCloudy, .cloudy]
        let covers = order.map { Atmosphere(condition: $0).cloudCover }
        #expect(covers == covers.sorted())
        #expect(Atmosphere(condition: .partlyCloudy, cloudCover: 0.6).cloudCover == 0.6)
        // В ненастье облачность из описания важнее данных
        #expect(Atmosphere(condition: .heavyRain, cloudCover: 0.2).cloudCover == 1)
    }

    @Test("Ветер, туман, дымка, позёмка, жара и мороз")
    func otherPhenomena() {
        #expect(Atmosphere(condition: .windy).wind > Atmosphere(condition: .breezy).wind)
        #expect(Atmosphere(condition: .clear, windKmh: 60).wind >= 0.9)
        #expect(Atmosphere(condition: .foggy).fog == 1)
        #expect(Atmosphere(condition: .smoky).veil == .smoke)
        #expect(Atmosphere(condition: .blowingDust).blowingDust > 0)
        #expect(Atmosphere(condition: .blizzard).blowingSnow > 0)
        #expect(Atmosphere(condition: .hot).heat)
        #expect(Atmosphere(condition: .frigid).frost)
        #expect(Atmosphere(condition: .sunShowers).sunThrough)
    }

    @Test("Погода испытания переводится в атмосферу")
    func eventWeather() {
        #expect(Atmosphere(event: .snow).isSnowy)
        #expect(Atmosphere(event: .sand).blowingDust > 0)
        #expect(Atmosphere(event: .rain).precipitation == .rain)
        #expect(Atmosphere(event: .clear) == .fair)
    }

    @Test("Молния вспыхивает только в грозу и ненадолго")
    func lightningFlash() {
        #expect(LightningLayer.flash(0, at: 100).amount == 0)
        let samples = stride(from: 0.0, to: 60, by: 0.05).map { LightningLayer.flash(1, at: $0).amount }
        let lit = samples.filter { $0 > 0.01 }.count
        #expect(lit > 0)
        #expect(Double(lit) / Double(samples.count) < 0.2)
    }
}
