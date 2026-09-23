import SwiftUI

struct RouteView: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.route.title).font(.title2.weight(.semibold))
                        Text("\(engine.route.season) · \(Fmt.km(engine.route.totalKm)) км · \(engine.route.stops.count) стоянок")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                    }
                    .padding(.bottom, 20)

                    ForEach(Array(engine.route.stops.enumerated()), id: \.element.id) { index, stop in
                        StopRow(
                            stop: stop,
                            state: rowState(for: stop),
                            isLast: index == engine.route.stops.count - 1,
                            kmAway: stop.km - engine.totalKm
                        )
                    }
                }
                .padding(16)
            }
            .background(Color.sand.ignoresSafeArea())
            .navigationTitle("Маршрут")
            .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
        }
        .foregroundStyle(Color.ink)
    }

    private func rowState(for stop: Stop) -> StopRow.State {
        if stop.id == engine.currentStop.id && !engine.isFinished { return .current }
        return stop.km <= engine.totalKm ? .reached : .upcoming
    }
}

struct StopRow: View {
    enum State { case reached, current, upcoming }

    let stop: Stop
    let state: State
    let isLast: Bool
    let kmAway: Double

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(state == .upcoming ? Color.sandDeep : Color.terracotta)
                        .frame(width: 30, height: 30)
                    Text(stop.emoji).font(.system(size: 15))
                }
                if !isLast {
                    Rectangle()
                        .fill(state == .reached ? Color.terracotta : Color.sandDeep)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            Group {
                if state == .upcoming {
                    content
                } else {
                    NavigationLink(value: stop) { content }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stop.name)
                    .font(.headline)
                    .foregroundStyle(state == .upcoming ? Color.inkSoft : Color.ink)
                Spacer()
                if state == .upcoming {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.inkSoft)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            Text(stop.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
            Text(state == .upcoming
                 ? "\(Fmt.km(stop.km)) км · ещё \(Fmt.km(kmAway)) км"
                 : (state == .current ? "\(Fmt.km(stop.km)) км · аул здесь" : "\(Fmt.km(stop.km)) км · пройдено"))
                .font(.caption)
                .foregroundStyle(state == .current ? Color.terracotta : Color.inkSoft)
        }
        .card()
    }
}
