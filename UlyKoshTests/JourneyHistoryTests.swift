import Foundation
import Testing
@testable import UlyKosh

@MainActor
struct JourneyHistoryTests {
    @Test("Смена пути в дороге: прежний уходит в архив, новый начинается с нуля, дневник сохраняется")
    func switchMidway() async {
        let h = await Harness(start: Fixtures.spring)
        h.walk(km: 20)
        h.engine.setNote("Первый день", for: DayKey.key(Fixtures.spring))
        let firstRoute = h.engine.route
        h.clock.advance(days: 1)
        h.walk(km: 5)
        let walkedBefore = h.engine.totalKm
        await h.engine.startJourney(heroName: "", routeId: SummerRoute.route.id)

        #expect(h.engine.route.id == SummerRoute.route.id)
        #expect(h.engine.totalKm == 0)
        let record = h.engine.state?.history.last
        #expect(record?.routeId == firstRoute.id)
        #expect(record?.finished == false)
        #expect(abs((record?.km ?? 0) - walkedBefore) < 0.001)

        // Шаги после смены идут уже новому пути.
        h.walk(km: 3)
        #expect(abs(h.engine.totalKm - 3) < 0.01)

        let days = h.engine.journalDays
        #expect(days.count == 2)
        #expect(days.last?.note == "Первый день")
        #expect(abs(days[0].walkedKm - 8) < 0.01)
        #expect(days[0].routeTitle == SummerRoute.route.endpoints)
        #expect(h.engine.journeySummaries.count == 2)
        #expect(h.engine.journeySummaries[0].segment.isCurrent)
        #expect(abs(h.engine.journeySummaries[1].km - walkedBefore) < 0.001)
    }

    @Test("После финиша: итоги показываются один раз, км после финиша в новый путь не переходят")
    func afterFinish() async {
        let h = await Harness(start: Fixtures.spring)
        h.walk(km: h.engine.route.totalKm + 1)
        #expect(h.engine.isFinished)
        #expect(h.engine.state?.finishSeen == false)
        h.engine.markFinishSeen()
        #expect(h.engine.state?.finishSeen == true)

        h.clock.advance(days: 1)
        h.walk(km: 4)
        await h.engine.startJourney(heroName: "", routeId: SummerRoute.route.id)
        #expect(h.engine.totalKm == 0)
        #expect(!h.engine.isFinished)
        #expect(h.engine.state?.finishSeen == false)
        let record = h.engine.state?.history.last
        #expect(record?.finished == true)
        #expect(record?.km == SpringRoute.route.totalKm)
        #expect(record?.endedAt == Fixtures.spring)

        let finishDay = h.engine.journalDays.last
        #expect(finishDay?.finishedRoutes == [SpringRoute.route.endpoints])
    }

    @Test("Путь без единого шага в архив не попадает")
    func emptyNotArchived() async {
        let h = await Harness(start: Fixtures.spring)
        await h.engine.startJourney(heroName: "", routeId: SummerRoute.route.id)
        #expect(h.engine.state?.history.isEmpty == true)
    }

    @Test("Старое сохранение без новых полей: дневник начинается со старта пути")
    func legacyDecode() throws {
        let start = Fixtures.spring
        let json = """
        {"routeId":"spring","aulName":"Путник","startDate":\(start.timeIntervalSinceReferenceDate),"strideMeters":0.7,
         "healthSteps":{},"healthDistanceKm":{},"sourceSettings":{},"debugSteps":{},"eventStatus":{}}
        """
        let state = try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
        #expect(state.journalStart == start)
        #expect(state.history.isEmpty)
        #expect(state.startBaselineKm == 0)
    }
}
