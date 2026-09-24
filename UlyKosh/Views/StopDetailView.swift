import SwiftUI

struct StopDetailView: View {
    let stop: Stop
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SceneView(terrain: stop.terrain, phase: .dusk, showCaravan: false)
                        .frame(height: geo.size.height * 0.36)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.6), value: appeared)

                    VStack(alignment: .leading, spacing: 20) {
                        VStack(spacing: 6) {
                            Text(stop.name)
                                .font(.display(32, weight: .regular))
                                .foregroundStyle(Color.gold)
                                .multilineTextAlignment(.center)
                            Text("\(stop.subtitle) · \(Fmt.km(stop.km)) км от начала пути")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.ash)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)

                        Text(stop.legend)
                            .font(.system(size: 16))
                            .lineSpacing(4)
                            .foregroundStyle(Color.parchment)

                        if !stop.fauna.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionTitle(text: "Кого здесь встретишь")
                                ForEach(stop.fauna) { fauna in
                                    HStack(alignment: .top, spacing: 12) {
                                        PictogramView(kind: fauna.icon, size: 30)
                                            .frame(width: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(fauna.name)
                                                .font(.display(17, weight: .regular))
                                                .foregroundStyle(Color.parchment)
                                            Text(fauna.note)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.ash)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }

                        if let person = stop.character {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionTitle(text: "К аулу присоединяется")
                                CharacterCard(character: person)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.easeOut(duration: 0.55).delay(0.15), value: appeared)
                }
            }
            .ignoresSafeArea(edges: .top)
            .onAppear { appeared = true }
        }
        .background(Color.night.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct CharacterCard: View {
    let character: Character

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PictogramView(kind: character.icon, size: 30)
                .frame(width: 52, height: 52)
                .background(Color.panel, in: Circle())
                .overlay(Circle().stroke(Color.hairline))
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.display(19, weight: .regular))
                    .foregroundStyle(Color.parchment)
                Text(character.role)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.gold)
                Text(character.story)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
                    .padding(.top, 2)
            }
        }
    }
}
