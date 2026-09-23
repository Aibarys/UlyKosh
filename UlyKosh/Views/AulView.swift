import SwiftUI

struct AulView: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    herdSection
                    peopleSection
                    eventsSection
                }
                .padding(16)
            }
            .background(Color.sand.ignoresSafeArea())
            .navigationTitle("Аул")
        }
        .foregroundStyle(Color.ink)
    }

    private var herdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Стадо")
            HStack(spacing: 12) {
                HerdTile(emoji: "🐑", count: engine.herd.sheep, name: "овцы")
                HerdTile(emoji: "🐎", count: engine.herd.horses, name: "лошади")
                HerdTile(emoji: "🐫", count: engine.herd.camels, name: "верблюды")
            }
            Text("Стадо растёт с каждым километром пути и за пройденные испытания.")
                .font(.caption)
                .foregroundStyle(Color.inkSoft)
        }
        .card()
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Люди аула · \(engine.joinedCharacters.count)")
            ForEach(engine.joinedCharacters) { person in
                CharacterCard(character: person)
                if person.id != engine.joinedCharacters.last?.id {
                    Divider()
                }
            }
            if let next = engine.route.stops.first(where: { $0.km > engine.totalKm && $0.character != nil }),
               let person = next.character {
                Divider()
                Text("Следующим присоединится \(person.role.lowercased()) на стоянке \(next.name)")
                    .font(.caption)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .card()
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Испытания")
            ForEach(engine.route.events) { event in
                HStack(alignment: .top, spacing: 12) {
                    Text(event.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.headline)
                        Text(statusText(for: event))
                            .font(.subheadline)
                            .foregroundStyle(statusColor(for: event))
                    }
                }
            }
        }
        .card()
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
        case .completed: return .steppe
        case .active: return .terracotta
        default: return .inkSoft
        }
    }
}

struct HerdTile: View {
    let emoji: String
    let count: Int
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            Text(emoji).font(.title)
            Text(count.formatted()).font(.title3.weight(.bold).monospacedDigit())
            Text(name).font(.caption).foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
