import SwiftUI

struct RouteView: View {
    @Environment(GameEngine.self) private var engine
    @State private var showStops = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if let world = MapWorld.shared {
                    KazakhstanMapView(world: world, stops: engine.route.stops)
                } else {
                    Text("Карта недоступна")
                        .foregroundStyle(Color.ash)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                header
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
            .sheet(isPresented: $showStops) {
                StopListSheet()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color.night)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.route.title)
                    .font(.display(22, weight: .regular))
                    .foregroundStyle(Color.gold)
                Text("\(engine.route.season) · \(Fmt.km(engine.totalKm)) из \(Fmt.km(engine.route.totalKm)) км")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ash)
            }
            Spacer()
            Button {
                showStops = true
            } label: {
                Label("Стоянки", systemImage: "list.bullet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.night.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(Color.gold.opacity(0.45)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .background(
            LinearGradient(colors: [Color.night.opacity(0.95), Color.night.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }
}

/// Список стоянок в выдвижной панели.
struct StopListSheet: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(engine.route.stops.enumerated()), id: \.element.id) { index, stop in
                        StopRow(
                            stop: stop,
                            state: rowState(for: stop),
                            isLast: index == engine.route.stops.count - 1,
                            kmAway: stop.km - engine.totalKm,
                            index: index,
                            revealed: true
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Stop.self) { StopDetailView(stop: $0) }
        }
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
    let index: Int
    let revealed: Bool

    private var delay: Double { Double(index) * 0.09 }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(Color.gold.opacity(state == .upcoming ? 0.35 : 1), lineWidth: 1)
                        .frame(width: 12, height: 12)
                    if state == .current {
                        PulsingDot()
                    } else if state == .reached {
                        Circle().fill(Color.gold).frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 6)
                .scaleEffect(revealed ? 1 : 0.2)
                .opacity(revealed ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.35).delay(delay), value: revealed)
                if !isLast {
                    Rectangle()
                        .fill(Color.gold.opacity(state == .reached ? 0.6 : 0.18))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: revealed ? 1 : 0, anchor: .top)
                        .animation(.easeOut(duration: 0.45).delay(delay + 0.12), value: revealed)
                }
            }
            .frame(width: 12)

            Group {
                if state == .upcoming {
                    content
                } else {
                    NavigationLink(value: stop) { content }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, isLast ? 0 : 22)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
            .animation(.easeOut(duration: 0.5).delay(delay + 0.05), value: revealed)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name)
                    .font(.display(19, weight: .regular))
                    .foregroundStyle(state == .upcoming ? Color.ash : Color.parchment)
                Text(stop.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
                Text(state == .upcoming
                     ? "\(Fmt.km(stop.km)) км · ещё \(Fmt.km(kmAway)) км"
                     : (state == .current ? "\(Fmt.km(stop.km)) км · аул здесь" : "\(Fmt.km(stop.km)) км · пройдено"))
                    .font(.system(size: 12))
                    .foregroundStyle(state == .upcoming ? Color.ash.opacity(0.7) : Color.gold)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: state == .upcoming ? "lock" : "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Color.ash)
                .padding(.top, 6)
        }
        .contentShape(Rectangle())
    }
}

/// Текущая стоянка: золотая точка с расходящимся кольцом.
struct PulsingDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gold, lineWidth: 1)
                .frame(width: 12, height: 12)
                .scaleEffect(pulse ? 2.6 : 1)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(Color.gold)
                .frame(width: 12, height: 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
