import Foundation
import Testing
@testable import UlyKosh

/// Учёт шагов и расстояния по источникам «Здоровья».
@MainActor
struct AggregationTests {
    let iphone = "com.apple.health.iphone"
    let band = "com.qutty.band"
    let today = Fixtures.date(2026, 9, 28, 9)
    func hour(_ h: Int) -> Date { Fixtures.date(2026, 9, 28, h) }

    @Test("Один источник с расстоянием: километры из расстояния, шаги как есть")
    func singleSourceWithDistance() {
        let steps = [hour(10): [iphone: 1200.0], hour(11): [iphone: 800.0]]
        let km = [hour(10): [iphone: 0.9], hour(11): [iphone: 0.6]]
        let totals = GameEngine.aggregate(steps: steps, km: km, settings: [:], stride: 0.7, today: today)
        let key = DayKey.key(today)
        #expect(totals.steps[key] == 2000)
        #expect(abs((totals.km[key] ?? 0) - 1.5) < 0.0001)
    }

    @Test("Телефон и браслет считали одну прогулку: шаги не удваиваются, расстояние от телефона")
    func overlappingSourcesDedup() {
        let steps = [hour(10): [iphone: 1000.0, band: 1100.0]]
        let km = [hour(10): [iphone: 0.75]]
        let totals = GameEngine.aggregate(steps: steps, km: km, settings: [:], stride: 0.7, today: today)
        let key = DayKey.key(today)
        #expect(totals.steps[key] == 1100)
        // 100 лишних шагов браслета сверх телефона переводятся по длине шага
        #expect(abs((totals.km[key] ?? 0) - (0.75 + 100 * 0.7 / 1000)) < 0.0001)
    }

    @Test("Беговая дорожка: телефон молчит, шаги браслета идут в километры по длине шага")
    func treadmillBandOnly() {
        let steps = [hour(19): [band: 3000.0]]
        let km: [Date: [String: Double]] = [hour(10): [iphone: 0.5]]
        let totals = GameEngine.aggregate(steps: steps, km: km, settings: [:], stride: 0.7, today: today)
        let key = DayKey.key(today)
        #expect(totals.steps[key] == 3000)
        #expect(abs((totals.km[key] ?? 0) - (0.5 + 2.1)) < 0.0001)
    }

    @Test("Ночной фильтр отбрасывает шаги источника с 23:00 до 06:00 и не трогает дневные")
    func nightFilter() {
        let steps = [hour(2): [band: 900.0], hour(23): [band: 400.0], hour(12): [band: 500.0]]
        let settings = [band: SourceSetting(enabled: true, nightFilter: true)]
        let totals = GameEngine.aggregate(steps: steps, km: [:], settings: settings, stride: 0.7, today: today)
        let key = DayKey.key(today)
        #expect(totals.steps[key] == 500)
        #expect(abs((totals.km[key] ?? 0) - 0.35) < 0.0001)
        // Без фильтра ночные шаги учитываются
        let plain = GameEngine.aggregate(steps: steps, km: [:], settings: [:], stride: 0.7, today: today)
        #expect(plain.steps[key] == 1800)
    }

    @Test("Выключенный источник не учитывается ни в шагах, ни в расстоянии")
    func disabledSource() {
        let steps = [hour(10): [iphone: 1000.0, band: 4000.0]]
        let km = [hour(10): [iphone: 0.7]]
        let settings = [band: SourceSetting(enabled: false)]
        let totals = GameEngine.aggregate(steps: steps, km: km, settings: settings, stride: 0.7, today: today)
        let key = DayKey.key(today)
        #expect(totals.steps[key] == 1000)
        #expect(abs((totals.km[key] ?? 0) - 0.7) < 0.0001)
    }

    @Test("Шаги за сегодня раскладываются по источникам для экрана настроек")
    func todayBySource() {
        let steps = [hour(10): [iphone: 1000.0, band: 1100.0], hour(11): [band: 300.0]]
        let totals = GameEngine.aggregate(steps: steps, km: [:], settings: [:], stride: 0.7, today: today)
        #expect(totals.todayBySource[iphone] == 1000)
        #expect(totals.todayBySource[band] == 1400)
    }
}
