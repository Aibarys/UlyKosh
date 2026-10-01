import Foundation
import Testing
@testable import UlyKosh

@MainActor
struct EngineTests {
    @Test("Весной стартует весенний маршрут, осенью — осенний")
    func routeBySeason() async {
        let spring = await Harness(start: Fixtures.spring)
        #expect(spring.engine.route.id == SpringRoute.route.id)
        let autumn = await Harness(start: Fixtures.autumn)
        #expect(autumn.engine.route.id == AutumnRoute.route.id)
    }

    @Test("В день старта километров нет, дальше аул идёт сам по 0.5 км в день")
    func passiveDrift() async {
        let h = await Harness(start: Fixtures.spring)
        #expect(h.engine.totalKm == 0)
        #expect(h.engine.dayNumber == 1)
        h.clock.advance(days: 3)
        #expect(abs(h.engine.totalKm - 1.5) < 0.0001)
        #expect(h.engine.dayNumber == 4)
    }

    @Test("Отладочные шаги переводятся по длине шага, километры не превышают длину маршрута")
    func debugStepsAndCap() async {
        let h = await Harness(start: Fixtures.spring)
        h.engine.addDebugSteps(10_000)
        #expect(abs(h.engine.totalKm - 7.0) < 0.0001)
        #expect(h.engine.stepsToday == 10_000)
        h.engine.addDebugSteps(2_000_000)
        #expect(h.engine.totalKm == h.engine.route.totalKm)
        #expect(h.engine.isFinished)
    }

    @Test("Расстояние из «Здоровья» имеет приоритет над шагами за тот же день")
    func healthDistanceWins() async {
        let h = await Harness(start: Fixtures.autumn)
        let hour = Fixtures.date(2026, 9, 28, 8)
        h.engine.ingest(hourlySteps: [hour: ["iphone": 10_000]], hourlyKm: [hour: ["iphone": 8.2]])
        #expect(abs(h.engine.kmToday - 8.2) < 0.0001)
        #expect(h.engine.stepsToday == 10_000)
        #expect(h.engine.usesHealthDistance)
    }

    @Test("Стоянка достигается, встреча попадает в дневник, приходит уведомление")
    func reachingStop() async {
        var h = await Harness(start: Fixtures.spring)
        let log = h.recordNotifications()
        let otyrar = h.engine.route.stops[1]
        h.walk(km: otyrar.km + 0.1)
        #expect(h.engine.currentStop.id == otyrar.id)
        #expect(h.engine.metPeople.map(\.id).contains(otyrar.character!.id))
        #expect(log.ids().contains("stop-\(otyrar.id)"))
    }

    @Test("Испытание: запускается на триггере, засчитывается и попадает в дневник")
    func eventCompletes() async {
        var h = await Harness(start: Fixtures.spring)
        let log = h.recordNotifications()
        let event = h.engine.route.events[0]
        h.walk(km: event.triggerKm + 0.5)
        #expect(h.engine.activeEvent?.event.id == event.id)
        #expect(log.ids().contains("event-\(event.id)-start"))
        h.walk(km: event.goalKm + 0.5)
        #expect(h.engine.activeEvent == nil)
        if case .completed = h.engine.status(of: event) {} else { Issue.record("испытание должно быть завершено") }
        #expect(log.ids().contains("event-\(event.id)-done"))
        // награда + рост стада за пройденные километры
        #expect(h.engine.completedEvents.map(\.id).contains(event.id))
    }

    @Test("Испытание проваливается по дедлайну без записи в дневнике")
    func eventFails() async {
        var h = await Harness(start: Fixtures.spring)
        let log = h.recordNotifications()
        let event = h.engine.route.events[0]
        h.walk(km: event.triggerKm + 0.5)
        h.clock.advance(days: Double(event.days) + 1)
        h.engine.addDebugSteps(0)
        if case .failed = h.engine.status(of: event) {} else { Issue.record("испытание должно провалиться") }
        #expect(log.ids().contains("event-\(event.id)-fail"))
        #expect(h.engine.completedEvents.isEmpty)
    }

    @Test("Выполненное до дедлайна испытание не проваливается, даже если приложение открыли позже")
    func lateOpenStillCompletes() async {
        let h = await Harness(start: Fixtures.spring)
        let event = h.engine.route.events[0]
        h.walk(km: event.triggerKm + event.goalKm + 1)
        h.clock.advance(days: 30)
        h.engine.addDebugSteps(0)
        if case .completed = h.engine.status(of: event) {} else { Issue.record("должно быть completed") }
    }

    @Test("Финиш маршрута ставит отметку и шлёт уведомление один раз")
    func finish() async {
        var h = await Harness(start: Fixtures.spring)
        let log = h.recordNotifications()
        h.walk(km: h.engine.route.totalKm + 1)
        #expect(h.engine.isFinished)
        #expect(h.engine.nextStop == nil)
        h.walk(km: 5)
        #expect(log.ids().filter { $0 == "finish" }.count == 1)
    }

    @Test("Состояние переживает перезапуск")
    func persistence() async {
        let dir = Fixtures.tempDirectory()
        let clock = TestClock(Fixtures.spring)
        let first = GameEngine(storeDirectory: dir, clock: { clock.now })
        await first.load()
        await first.startJourney(heroName: "Ерлан")
        first.addDebugSteps(5_000)

        let second = GameEngine(storeDirectory: dir, clock: { clock.now })
        await second.load()
        #expect(second.state?.heroName == "Ерлан")
        #expect(second.stepsToday == 5_000)
        #expect(second.route.id == first.route.id)
    }

    @Test("Сброс кочевья очищает состояние")
    func reset() async {
        let h = await Harness(start: Fixtures.spring)
        h.walk(km: 10)
        h.engine.resetJourney()
        #expect(h.engine.state == nil)
        #expect(h.engine.totalKm == 0)
    }
}
