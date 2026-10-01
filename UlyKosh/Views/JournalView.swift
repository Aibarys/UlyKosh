import SwiftUI

/// Дорожный дневник: где был путник, кого встретил, что видел, какие испытания прошёл.
struct JournalView: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeader(title: engine.state?.heroName ?? GameEngine.defaultHeroName,
                                 subtitle: String(localized: "День \(engine.dayNumber) · \(Fmt.km(engine.totalKm)) км пути"))

                    summary
                    placesSection
                    if !engine.metPeople.isEmpty { peopleSection }
                    faunaSection
                    if !engine.route.events.isEmpty { eventsSection }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            SummaryTile(icon: .yurt, count: max(0, engine.reachedStops.count - 1), total: engine.route.stops.count - 1, name: String(localized: "стоянок"))
            SummaryTile(icon: .saiga, count: engine.seenFauna.count, total: nil, name: String(localized: "встреч в природе"))
            SummaryTile(icon: .snow, count: engine.completedEvents.count, total: engine.route.events.count, name: String(localized: "испытаний"))
        }
        .panel()
    }

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: String(localized: "Пройденные места"))
            ForEach(engine.reachedStops.reversed()) { stop in
                NavigationLink(value: stop) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(.display(17, weight: .regular))
                                .foregroundStyle(Color.parchment)
                            Text(stop.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ash)
                        }
                        Spacer()
                        Text("\(Fmt.km(stop.km)) км")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.gold)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let next = engine.nextStop {
                Text("Впереди: \(next.name), через \(Fmt.km(engine.kmToNextStop)) км")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Color.ash)
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: String(localized: "Встречи в пути"))
            ForEach(engine.metPeople) { person in
                CharacterCard(character: person)
                if person.id != engine.metPeople.last?.id {
                    Rectangle().fill(Color.hairline).frame(height: 0.5)
                }
            }
        }
    }

    private var faunaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: String(localized: "Природа"))
            if engine.seenFauna.isEmpty {
                Text("Пока никого. Звери и растения появятся здесь, когда путник дойдёт до первой стоянки.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
            }
            ForEach(engine.seenFauna) { fauna in
                HStack(alignment: .top, spacing: 12) {
                    PictogramView(kind: fauna.icon, size: 26)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fauna.name)
                            .font(.display(16, weight: .regular))
                            .foregroundStyle(Color.parchment)
                        Text(fauna.note)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ash)
                    }
                }
            }
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: String(localized: "Испытания"))
            ForEach(engine.route.events) { event in
                HStack(alignment: .top, spacing: 12) {
                    PictogramView(kind: event.icon, size: 24, tint: statusColor(for: event))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.display(17, weight: .regular))
                            .foregroundStyle(Color.parchment)
                        Text(statusText(for: event))
                            .font(.system(size: 13))
                            .foregroundStyle(statusColor(for: event))
                    }
                }
            }
        }
    }

    private func statusText(for event: RouteEvent) -> String {
        switch engine.status(of: event) {
        case .none: return String(localized: "Ждёт на \(Fmt.km(event.triggerKm)) км")
        case .active: return String(localized: "Идёт сейчас: \(Fmt.km(event.goalKm)) км за \(Fmt.days(event.days))")
        case .completed: return event.rewardText
        case .failed: return String(localized: "Не успели. Путник справился, но без записи в дневнике")
        }
    }

    private func statusColor(for event: RouteEvent) -> Color {
        switch engine.status(of: event) {
        case .completed, .active: return .gold
        default: return .ash
        }
    }
}

struct SummaryTile: View {
    let icon: Pictogram
    let count: Int
    let total: Int?
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            PictogramView(kind: icon, size: 26)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.display(28, weight: .regular))
                    .foregroundStyle(Color.gold)
                if let total {
                    Text("/\(total)")
                        .font(.display(14, weight: .regular))
                        .foregroundStyle(Color.ash)
                }
            }
            .monospacedDigit()
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
