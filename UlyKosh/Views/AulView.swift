import SwiftUI

struct AulView: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeader(title: engine.state?.aulName ?? "Аул", subtitle: "День \(engine.dayNumber) · \(Fmt.km(engine.totalKm)) км пути")

                    herdSection
                    peopleSection
                    eventsSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var herdSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Стадо")
            HStack(spacing: 0) {
                HerdTile(icon: .sheep, count: engine.herd.sheep, name: "овцы")
                HerdTile(icon: .horse, count: engine.herd.horses, name: "лошади")
                HerdTile(icon: .camel, count: engine.herd.camels, name: "верблюды")
            }
            .panel()
            Text("Стадо растёт с каждым километром пути и за пройденные испытания.")
                .font(.system(size: 12))
                .foregroundStyle(Color.ash)
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Люди аула · \(engine.joinedCharacters.count)")
            ForEach(engine.joinedCharacters) { person in
                CharacterCard(character: person)
                if person.id != engine.joinedCharacters.last?.id {
                    Rectangle().fill(Color.hairline).frame(height: 0.5)
                }
            }
            if let next = engine.route.stops.first(where: { $0.km > engine.totalKm && $0.character != nil }),
               let person = next.character {
                Rectangle().fill(Color.hairline).frame(height: 0.5)
                Text("Следующим присоединится \(person.role.lowercased()) на стоянке \(next.name)")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Color.ash)
            }
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Испытания")
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
        case .none: return "Ждёт на \(Fmt.km(event.triggerKm)) км"
        case .active: return "Идёт сейчас: \(Fmt.km(event.goalKm)) км за \(Fmt.days(event.days))"
        case .completed: return "Пройдено. \(event.rewardText)"
        case .failed: return "Не успели. Аул справился, но без награды"
        }
    }

    private func statusColor(for event: RouteEvent) -> Color {
        switch engine.status(of: event) {
        case .completed, .active: return .gold
        default: return .ash
        }
    }
}

struct HerdTile: View {
    let icon: Pictogram
    let count: Int
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            PictogramView(kind: icon, size: 32)
            Text(count.formatted())
                .font(.display(30, weight: .regular))
                .foregroundStyle(Color.gold)
                .monospacedDigit()
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Color.ash)
        }
        .frame(maxWidth: .infinity)
    }
}
