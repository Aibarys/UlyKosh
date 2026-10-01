import Charts
import SwiftUI

/// Отчёт за один день пути: километры, шаги по часам, погода, события и заметка.
struct DayDetailView: View {
    @Environment(GameEngine.self) private var engine
    let dayKey: String
    @State private var note = ""
    @State private var loaded = false
    @FocusState private var editing: Bool

    var body: some View {
        ScrollView {
            if let day = engine.journalDays.first(where: { $0.key == dayKey }) {
                content(day)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .onAppear {
                        guard !loaded else { return }
                        note = day.note ?? ""
                        loaded = true
                    }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.night.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.night, for: .navigationBar)
        .toolbar {
            if editing {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Готово") { editing = false }.tint(.gold)
                    }
                }
            }
        }
        .onChange(of: editing) { _, isEditing in
            if !isEditing { save() }
        }
        .onDisappear { save() }
    }

    private func save() {
        guard loaded else { return }
        engine.setNote(note, for: dayKey)
    }

    @ViewBuilder
    private func content(_ day: JournalDay) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ScreenHeader(title: day.date.formatted(.dateTime.day().month(.wide)),
                         subtitle: String(localized: "День \(day.number) · \(day.date.formatted(.dateTime.weekday(.wide)))"))

            hero(day)
            details(day)
            if let hourly = day.hourly, hourly.contains(where: { $0 > 0 }) {
                hourlyChart(hourly)
            }
            if day.hasEvents { events(day) }
            if !day.fauna.isEmpty { fauna(day) }
            noteEditor
        }
    }

    private func hero(_ day: JournalDay) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.km(day.dayKm))
                        .font(.display(54, weight: .light))
                        .foregroundStyle(Color.gold)
                    Text("км").font(.display(18, weight: .regular)).foregroundStyle(Color.ash)
                }
                Text(String(localized: "\(Fmt.steps(day.steps)) шагов"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.parchment)
            }
            .monospacedDigit()
            Spacer()
            if let weather = day.weather {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: weather.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 30))
                        .foregroundStyle(Color.gold)
                    Text("\(Int(weather.temperature.rounded()))°")
                        .font(.display(20, weight: .regular))
                        .foregroundStyle(Color.parchment)
                    if let place = weather.place {
                        Text(place).font(.system(size: 11)).foregroundStyle(Color.ash)
                    }
                }
            }
        }
    }

    private func details(_ day: JournalDay) -> some View {
        VStack(spacing: 0) {
            DetailRow(title: String(localized: "Пешком"), value: "\(Fmt.km(day.walkedKm)) км")
            if day.passiveKm > 0 {
                DetailRow(title: String(localized: "Путник прошёл сам"), value: "\(Fmt.km(day.passiveKm)) км")
            }
            DetailRow(title: String(localized: "С начала пути"), value: "\(Fmt.km(day.totalKm)) км")
            if let peak = day.peakHour {
                DetailRow(title: String(localized: "Самый активный час"), value: String(format: "%02d:00–%02d:00", peak, (peak + 1) % 24))
            }
            if let hourly = day.hourly {
                let hours = hourly.filter { $0 >= 250 }.count
                if hours > 0 {
                    DetailRow(title: String(localized: "Часов в движении"), value: "\(hours)")
                }
            }
            DetailRow(title: String(localized: "Активный день"),
                      value: day.isActive ? String(localized: "да") : String(localized: "нет, меньше 5 000 шагов"),
                      isLast: true)
        }
        .panel()
    }

    private func hourlyChart(_ hourly: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: String(localized: "Шаги по часам"))
            Chart {
                ForEach(0..<24, id: \.self) { h in
                    BarMark(x: .value("hour", h), y: .value("steps", hourly[h]), width: .fixed(9))
                        .foregroundStyle(Color.gold.opacity(hourly[h] == hourly.max() ? 1 : 0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) { Text(String(format: "%02d", h)) }
                    }
                    .foregroundStyle(Color.ash)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel().foregroundStyle(Color.ash)
                }
            }
            .frame(height: 140)
        }
        .panel()
    }

    private func events(_ day: JournalDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: String(localized: "События дня"))
            ForEach(day.stops) { stop in
                NavigationLink(value: stop) {
                    HStack(alignment: .top, spacing: 12) {
                        PictogramView(kind: .yurt, size: 22).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(.display(17, weight: .regular))
                                .foregroundStyle(Color.parchment)
                            Text(stop.character.map { String(localized: "Встреча: \($0.name)") } ?? stop.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ash)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.ash)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(day.eventsStarted) { eventRow($0, String(localized: "Началось испытание"), active: true) }
            ForEach(day.eventsCompleted) { eventRow($0, $0.rewardText, active: true) }
            ForEach(day.eventsFailed) { eventRow($0, String(localized: "Не успели, но путник справился"), active: false) }
        }
    }

    private func eventRow(_ event: RouteEvent, _ text: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PictogramView(kind: event.icon, size: 22, tint: active ? .gold : .ash).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.display(17, weight: .regular))
                    .foregroundStyle(Color.parchment)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? Color.gold : Color.ash)
            }
        }
    }

    private func fauna(_ day: JournalDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: String(localized: "Встречи в природе"))
            ForEach(day.fauna) { f in
                HStack(alignment: .top, spacing: 12) {
                    PictogramView(kind: f.icon, size: 24).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(.display(16, weight: .regular)).foregroundStyle(Color.parchment)
                        Text(f.note).font(.system(size: 12)).foregroundStyle(Color.ash)
                    }
                }
            }
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: String(localized: "Заметка"))
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Как прошёл день? Где гуляли, что видели…")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(Color.ash)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $note)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.parchment)
                    .scrollContentBackground(.hidden)
                    .focused($editing)
                    .frame(minHeight: 110)
            }
            .padding(8)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(editing ? Color.gold.opacity(0.5) : Color.hairline))
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(Color.ash)
                Spacer()
                Text(value).foregroundStyle(Color.parchment).monospacedDigit()
            }
            .font(.system(size: 14))
            .padding(.vertical, 9)
            if !isLast { Rectangle().fill(Color.hairline).frame(height: 0.5) }
        }
    }
}
