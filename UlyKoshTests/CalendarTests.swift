import Foundation
import Testing
@testable import UlyKosh

struct CalendarTests {
    @Test("Сезон определяется по месяцу")
    func seasons() {
        #expect(Season.current(Fixtures.date(2026, 3, 1)) == .spring)
        #expect(Season.current(Fixtures.date(2026, 7, 15)) == .summer)
        #expect(Season.current(Fixtures.date(2026, 9, 28)) == .autumn)
        #expect(Season.current(Fixtures.date(2026, 12, 31)) == .winter)
        #expect(Season.current(Fixtures.date(2026, 2, 1)) == .winter)
    }

    @Test("Маршрут выбирается по сезону старта")
    func routeForStart() {
        #expect(Routes.forStart(Fixtures.date(2026, 4, 1)).id == SpringRoute.route.id)
        #expect(Routes.forStart(Fixtures.date(2026, 7, 1)).id == SummerRoute.route.id)
        #expect(Routes.forStart(Fixtures.date(2026, 10, 1)).id == AutumnRoute.route.id)
        #expect(Routes.forStart(Fixtures.date(2026, 1, 1)).id == WinterRoute.route.id)
        #expect(Set(Routes.all.map(\.id)).count == 4)
    }

    @Test("Фаза дня зависит от восхода и заката месяца")
    func skyPhases() {
        // Июнь: светло до девяти вечера
        #expect(SkyPhase.current(Fixtures.date(2026, 6, 20, 20, 0)) == .day)
        #expect(SkyPhase.current(Fixtures.date(2026, 6, 20, 21, 30)) == .dusk)
        #expect(SkyPhase.current(Fixtures.date(2026, 6, 20, 4, 30)) == .dawn)
        // Декабрь: темнеет к пяти
        #expect(SkyPhase.current(Fixtures.date(2026, 12, 20, 17, 30)) == .dusk)
        #expect(SkyPhase.current(Fixtures.date(2026, 12, 20, 19, 0)) == .night)
        #expect(SkyPhase.current(Fixtures.date(2026, 12, 20, 12, 0)) == .day)
    }

    @Test("Ключ дня стабилен внутри суток и меняется в полночь")
    func dayKey() {
        #expect(DayKey.key(Fixtures.date(2026, 9, 28, 0, 1)) == DayKey.key(Fixtures.date(2026, 9, 28, 23, 59)))
        #expect(DayKey.key(Fixtures.date(2026, 9, 28, 23, 59)) != DayKey.key(Fixtures.date(2026, 9, 29, 0, 0)))
    }

    @Test("Старое сохранение без новых полей читается")
    func tolerantDecoding() throws {
        let json = """
        {"routeId":"spring-syrdarya-ulytau","aulName":"Аул","startDate":700000000,"healthSteps":{"2026-04-15":1200}}
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(GameState.self, from: json)
        #expect(state.aulName == "Аул")
        #expect(state.healthSteps["2026-04-15"] == 1200)
        #expect(state.strideMeters == 0.7)
        #expect(state.sourceSettings.isEmpty)
        #expect(state.healthRequested == false)
    }

    @Test("Маршруты согласованы: стоянки по возрастанию км, события внутри маршрута, уникальные id")
    func routesConsistency() {
        for route in Routes.all {
            let kms = route.stops.map(\.km)
            #expect(kms == kms.sorted(), "стоянки \(route.id) не по порядку")
            #expect(Set(route.stops.map(\.id)).count == route.stops.count)
            #expect(Set(route.events.map(\.id)).count == route.events.count)
            for event in route.events {
                #expect(event.triggerKm + event.goalKm <= route.totalKm, "\(event.id) выходит за маршрут")
                #expect(event.days > 0 && event.goalKm > 0)
            }
            #expect(route.stops.allSatisfy { !$0.trailNotes.isEmpty && !$0.legend.isEmpty })
        }
    }
}
