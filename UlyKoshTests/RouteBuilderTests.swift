import Foundation
import Testing
@testable import UlyKosh

/// Свои маршруты: данные, прокладка по дорогам, стоянки, испытания, сохранение.
@MainActor
struct RouteBuilderTests {
    let places = PlaceStore.shared

    func place(_ ru: String) -> Place {
        places.places.first { $0.ru == ru && $0.rank <= 3 }!
    }

    @Test("Данные загружаются: тысячи населённых пунктов и связный граф дорог")
    func dataLoads() {
        #expect(places.places.count > 5000)
        #expect(RoadGraph.shared.nodes.count > 300)
        #expect(places.places.contains { $0.isCapital && $0.ru == "Астана" })
        #expect(!places.place(places.places[0].id)!.regionName.isEmpty)
    }

    @Test("Поиск понимает русское и казахское написание")
    func search() {
        #expect(places.search("Шымк").first?.ru == "Шымкент")
        #expect(places.search("Түркіс").contains { $0.ru == "Туркестан" })
        #expect(places.search("алмат").first?.ru == "Алматы")
        #expect(!places.search("").isEmpty)
    }

    @Test("Алматы → Астана: путь по дорогам реальной длины")
    func almatyAstana() throws {
        let route = try #require(RouteBuilder.build(from: place("Алматы"), to: place("Астана"), startDate: Fixtures.autumn))
        #expect(route.totalKm > 1100 && route.totalKm < 1400)
        #expect(route.stops.first?.placeId == place("Алматы").id)
        #expect(route.stops.last?.placeId == place("Астана").id)
        #expect(abs((route.stops.last?.km ?? 0) - route.totalKm) < 0.01)
    }

    @Test("Стоянки идут по порядку, разрыв между ними не больше 70 км")
    func stopSpacing() throws {
        let route = try #require(RouteBuilder.build(from: place("Кызылорда"), to: place("Караганда"), startDate: Fixtures.spring))
        let kms = route.stops.map(\.km)
        #expect(kms == kms.sorted())
        for (a, b) in zip(kms, kms.dropFirst()) {
            #expect(b - a <= 70, "разрыв \(Int(b - a)) км после \(Int(a)) км")
        }
        #expect(route.stops.count >= 8)
    }

    @Test("Знаковые места великих кочевий попадают в свой путь")
    func landmarks() throws {
        let route = try #require(RouteBuilder.build(from: place("Шымкент"), to: place("Кызылорда"), startDate: Fixtures.autumn))
        let shown = RouteBuilder.makeRoute(route)
        #expect(route.stops.contains { $0.kind == .landmark })
        #expect(shown.stops.contains { $0.legend.contains("Ясауи") })
    }

    @Test("Испытания соответствуют сезону и расставлены вдоль пути")
    func eventsBySeason() throws {
        let winter = try #require(RouteBuilder.build(from: place("Алматы"), to: place("Астана"), startDate: Fixtures.date(2026, 1, 10)))
        #expect(!winter.events.isEmpty)
        #expect(winter.events.allSatisfy { !["heat", "thunderstorm", "flood"].contains($0.template) })
        #expect(winter.events.allSatisfy { $0.triggerKm > 0 && $0.triggerKm < winter.totalKm })
        let summer = try #require(RouteBuilder.build(from: place("Алматы"), to: place("Астана"), startDate: Fixtures.date(2026, 7, 10)))
        #expect(summer.events.allSatisfy { !["buran", "frost"].contains($0.template) })
    }

    @Test("Свой путь сохраняется, переживает перезапуск и движок идёт по нему")
    func customJourney() async throws {
        let dir = Fixtures.tempDirectory()
        let clock = TestClock(Fixtures.autumn)
        let custom = try #require(RouteBuilder.build(from: place("Шымкент"), to: place("Туркестан")))
        let engine = GameEngine(storeDirectory: dir, clock: { clock.now })
        await engine.load()
        await engine.startJourney(heroName: "Айгерим", customRoute: custom)
        #expect(engine.route.isCustom)
        #expect(engine.route.path != nil)
        #expect(abs(engine.route.totalKm - custom.totalKm) < 0.01)

        engine.addDebugSteps(Int(custom.totalKm * 1000 / 0.7) + 10)
        #expect(engine.isFinished)
        #expect(engine.reachedStops.count == engine.route.stops.count)

        let again = GameEngine(storeDirectory: dir, clock: { clock.now })
        await again.load()
        #expect(again.state?.heroName == "Айгерим")
        #expect(again.route.isCustom)
        #expect(again.isFinished)
    }

    @Test("Новый путь сохраняет имя и настройки источников")
    func newJourneyKeepsSettings() async throws {
        let h = await Harness(start: Fixtures.autumn)
        h.engine.updateSetting(for: HealthSource(id: "band", name: "Band")) { $0.nightFilter = true }
        let custom = try #require(RouteBuilder.build(from: place("Шымкент"), to: place("Туркестан")))
        await h.engine.startJourney(heroName: "", customRoute: custom)
        #expect(h.engine.state?.heroName == "Тестовый путник")
        #expect(h.engine.state?.sourceSettings["band"]?.nightFilter == true)
    }
}
