import SwiftUI

struct StopDetailView: View {
    let stop: Stop

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text(stop.terrain).font(.system(size: 80))
                    Text(stop.name).font(.title.weight(.bold))
                    Text("\(stop.subtitle) · \(Fmt.km(stop.km)) км от кыстау")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                Text(stop.legend)
                    .font(.body)
                    .card()

                if !stop.fauna.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Кого здесь встретишь")
                        ForEach(stop.fauna) { fauna in
                            HStack(alignment: .top, spacing: 12) {
                                Text(fauna.emoji).font(.title)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fauna.name).font(.headline)
                                    Text(fauna.note).font(.subheadline).foregroundStyle(Color.inkSoft)
                                }
                            }
                        }
                    }
                    .card()
                }

                if let person = stop.character {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "К аулу присоединяется")
                        CharacterCard(character: person)
                    }
                    .card()
                }
            }
            .padding(16)
        }
        .background(Color.sand.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.ink)
    }
}

struct CharacterCard: View {
    let character: Character

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(character.emoji)
                .font(.system(size: 34))
                .frame(width: 52, height: 52)
                .background(Color.sandDeep.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name).font(.headline)
                Text(character.role).font(.caption.weight(.semibold)).foregroundStyle(Color.terracotta)
                Text(character.story).font(.subheadline).foregroundStyle(Color.inkSoft)
            }
        }
    }
}
