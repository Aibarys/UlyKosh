import Foundation
import Testing
@testable import UlyKosh

@MainActor
struct JournalTests {
    @Test("Дневник содержит каждый день пути, от сегодняшнего к первому")
    func everyDay() async {
        let h = await Harness(start: Fixtures.spring)
        h.walk(km: 7)
        h.clock.advance(days: 1)
        h.clock.advance(days: 1)
        h.walk(km: 3)
        let days = h.engine.journalDays
        #expect(days.map(\.number) == [3, 2, 1])
        #expect(days[0].isToday)
        #expect(abs(days[2].walkedKm - 7) < 0.01)
        #expect(days[1].walkedKm == 0)
        #expect(abs(days[0].walkedKm - 3) < 0.01)
        // Полкилометра за каждый завершённый день, сегодня — ещё нет.
        #expect(days[2].passiveKm == 0.5 && days[0].passiveKm == 0)
        // Итог последнего дня совпадает с километражем движка.
        #expect(abs(days[0].totalKm - h.engine.totalKm) < 0.0001)
    }

    @Test("Стоянка записывается в тот день, когда до неё дошли")
    func stopOnItsDay() async {
        let h = await Harness(start: Fixtures.spring)
        let first = h.engine.route.stops[1]
        h.walk(km: first.km / 2)
        h.clock.advance(days: 1)
        h.walk(km: first.km / 2 + 1)
        let days = h.engine.journalDays
        #expect(days[1].stops.map(\.id) == [h.engine.route.stops[0].id])
        #expect(days[0].stops.map(\.id) == [first.id])
        #expect(days[0].people == [first.character].compactMap { $0 })
    }

    @Test("Шаги по часам, погода и заметка попадают в свой день")
    func hourlyWeatherNote() async {
        let h = await Harness(start: Fixtures.autumn)
        let hour = Fixtures.date(2026, 9, 28, 8)
        h.engine.ingest(hourlySteps: [hour: ["iphone": 4_000]], hourlyKm: [hour: ["iphone": 3.0]])
        h.engine.addDebugSteps(1_000)
        h.engine.logWeather(WeatherNote(temperature: 12.4, condition: "cloudy", symbol: "cloud", place: "Павлодар"))
        h.engine.setNote("  Гулял по набережной  ", for: DayKey.key(Fixtures.autumn))
        let day = h.engine.journalDays[0]
        #expect(day.hourly?[8] == 4_000)
        #expect(day.hourly?[10] == 1_000)
        #expect(day.peakHour == 8)
        #expect(day.steps == 5_000)
        #expect(day.isActive)
        #expect(day.weather?.place == "Павлодар")
        #expect(day.note == "Гулял по набережной")
        h.engine.setNote("   ", for: day.key)
        #expect(h.engine.journalDays[0].note == nil)
    }

    @Test("Серия активных дней не обрывается, пока сегодня ещё не нагуляно")
    func streak() async {
        let h = await Harness(start: Fixtures.spring)
        h.engine.addDebugSteps(6_000)
        h.clock.advance(days: 1)
        h.engine.addDebugSteps(2_000)
        h.clock.advance(days: 1)
        h.engine.addDebugSteps(8_000)
        h.clock.advance(days: 1)
        h.engine.addDebugSteps(9_000)
        h.clock.advance(days: 1)
        let stats = h.engine.journalStats
        #expect(stats.days == 5)
        #expect(stats.currentStreak == 2)
        #expect(stats.longestStreak == 2)
        #expect(stats.activeDays == 3)
        #expect(stats.totalSteps == 25_000)
        #expect(abs((stats.bestDay?.km ?? 0) - 6.3) < 0.01)
    }

    @Test("Дневник и заметки переживают перезапуск")
    func persistence() async {
        let dir = Fixtures.tempDirectory()
        let clock = TestClock(Fixtures.autumn)
        let a = GameEngine(storeDirectory: dir, clock: { clock.now })
        await a.load()
        await a.startJourney(heroName: "Путник")
        a.addDebugSteps(3_000)
        a.setNote("Первый день", for: DayKey.key(Fixtures.autumn))
        let b = GameEngine(storeDirectory: dir, clock: { clock.now })
        await b.load()
        #expect(b.journalDays.first?.note == "Первый день")
        #expect(b.journalDays.first?.hourly?[10] == 3_000)
    }
}
