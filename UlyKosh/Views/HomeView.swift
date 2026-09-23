import SwiftUI

struct HomeView: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    SceneCard()
                    progressCard
                    if engine.isFinished { finishCard }
                    if let active = engine.activeEvent { EventCard(active: active) }
                    todayCard
                    encounterCard
                }
                .padding(16)
            }
            .background(Color.sand.ignoresSafeArea())
            .navigationTitle(engine.state?.aulName ?? "")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await engine.syncSteps() }
        }
        .foregroundStyle(Color.ink)
    }

    private var header: some View {
        HStack {
            Text("День \(engine.dayNumber) кочевья")
            Spacer()
            Text(engine.route.season)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.inkSoft)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.km(engine.totalKm))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("из \(Fmt.km(engine.route.totalKm)) км")
                    .foregroundStyle(Color.inkSoft)
            }
            ProgressView(value: engine.totalKm, total: engine.route.totalKm)
                .tint(Color.terracotta)

            if let next = engine.nextStop {
                HStack {
                    Text("\(next.emoji) \(next.name)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("через \(Fmt.km(engine.kmToNextStop)) км")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSoft)
                }
            } else {
                Text("Аул дошёл до жайляу")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .card()
    }

    private var todayCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.walk")
                .font(.title)
                .foregroundStyle(Color.steppe)
            VStack(alignment: .leading, spacing: 2) {
                Text("Сегодня")
                    .font(.caption)
                    .foregroundStyle(Color.inkSoft)
                Text("\(engine.stepsToday.formatted()) шагов")
                    .font(.headline)
                Text("≈ \(Fmt.km(engine.kmToday)) км пути")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer()
            if engine.healthStatus == .unavailable {
                Text("Здоровье недоступно")
                    .font(.caption2)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .card()
    }

    private var encounterCard: some View {
        Group {
            if let fauna = engine.encounterOfTheDay {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Сегодня в степи")
                    HStack(alignment: .top, spacing: 12) {
                        Text(fauna.emoji).font(.system(size: 36))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fauna.name).font(.headline)
                            Text(fauna.note)
                                .font(.subheadline)
                                .foregroundStyle(Color.inkSoft)
                        }
                    }
                }
                .card()
            }
        }
    }

    private var finishCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🎉 Аул дошёл до жайляу!")
                .font(.headline)
            Text("Кочевье окончено. Юрты стоят на склонах Ұлытау, кобылиц отпустили в табун, а вечером будет той. Осенью аул двинется обратно на юг.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
        }
        .card()
    }
}

struct SceneCard: View {
    @Environment(GameEngine.self) private var engine

    var body: some View {
        let target = engine.nextStop ?? engine.currentStop
        VStack(spacing: 12) {
            Text(target.terrain)
                .font(.system(size: 72))
                .padding(.top, 8)
            Text(engine.isFinished ? "Летние пастбища" : "Дорога к стоянке \(target.name)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ink)
            TrailView(stops: engine.route.stops, totalKm: engine.route.totalKm, km: engine.totalKm)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.sky.opacity(0.85), .sandDeep.opacity(0.6)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct TrailView: View {
    let stops: [Stop]
    let totalKm: Double
    let km: Double

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 14
            let width = geo.size.width - inset * 2
            let cy = geo.size.height - 10
            let x: (Double) -> CGFloat = { inset + width * CGFloat($0 / totalKm) }

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: width, height: 5)
                    .position(x: inset + width / 2, y: cy)
                Capsule()
                    .fill(Color.terracotta)
                    .frame(width: max(0, x(km) - inset), height: 5)
                    .position(x: inset + max(0, x(km) - inset) / 2, y: cy)
                ForEach(stops) { stop in
                    Circle()
                        .fill(stop.km <= km ? Color.terracotta : Color.white)
                        .overlay(Circle().stroke(Color.terracotta, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .position(x: x(stop.km), y: cy)
                }
                Text("🐫")
                    .font(.title)
                    .position(x: x(km), y: cy - 24)
            }
        }
        .frame(height: 64)
    }
}

struct EventCard: View {
    let active: ActiveEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(active.event.emoji).font(.title2)
                Text(active.event.title).font(.headline)
                Spacer()
                Text(active.daysLeft == 0 ? "последний день" : "осталось \(Fmt.days(active.daysLeft))")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.terracotta.opacity(0.15), in: Capsule())
            }
            Text(active.event.description)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
            ProgressView(value: active.progress)
                .tint(Color.terracotta)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.km(active.coveredKm)) из \(Fmt.km(active.event.goalKm)) км")
                Text("Награда: \(active.event.rewardText)")
            }
            .font(.caption)
            .foregroundStyle(Color.inkSoft)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.terracotta.opacity(0.5), lineWidth: 1.5)
        )
    }
}
