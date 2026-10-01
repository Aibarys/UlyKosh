import SwiftUI

/// Выбор своего пути: откуда и куда, предпросмотр по дорогам, старт.
struct RoutePickerView: View {
    var startTitle: String = String(localized: "В путь")
    let onStart: (CustomRoute) -> Void

    @State var from: Place?
    @State var to: Place?
    @State private var built: CustomRoute?
    @State private var preview: Route?
    @State private var building = false
    @State private var failed = false
    @State private var picking: Field?
    private var weather: WeatherStore { WeatherStore.shared }

    enum Field: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: String(localized: "Новый путь"),
                             subtitle: String(localized: "Выберите, откуда и куда идёт путник. Путь проляжет по дорогам Казахстана."))

                VStack(spacing: 0) {
                    fieldRow(title: String(localized: "Откуда"), place: from) { picking = .from }
                    Rectangle().fill(Color.hairline).frame(height: 0.5)
                    fieldRow(title: String(localized: "Куда"), place: to) { picking = .to }
                }
                .panel()
                .overlay(alignment: .trailing) {
                    Button {
                        swap(&from, &to)
                        rebuild()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color.gold)
                            .frame(width: 36, height: 36)
                            .background(Color.night, in: Circle())
                            .overlay(Circle().stroke(Color.gold.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                }

                Button {
                    useMyLocation()
                } label: {
                    Label("Начать от меня", systemImage: "location")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.gold)
                }
                .buttonStyle(.plain)

                if building {
                    HStack { Spacer(); ProgressView().tint(Color.gold); Spacer() }
                        .padding(.vertical, 30)
                } else if failed {
                    Text("Между этими пунктами не нашлось дороги. Попробуйте соседний город.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ash)
                } else if let built, let preview, let world = MapWorld.shared {
                    KazakhstanMapView(world: world, route: preview, km: 0, currentStopId: preview.stops.first?.id,
                                      isFinished: false, allowsNavigation: false)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .id("\(built.fromId)-\(built.toId)")

                    summary(built: built, route: preview)

                    Button {
                        onStart(built)
                    } label: {
                        Text(startTitle)
                            .font(.display(19, weight: .medium))
                            .foregroundStyle(Color.night)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.night.ignoresSafeArea())
        .onAppear { if built == nil, from != nil, to != nil { rebuild() } }
        .sheet(item: $picking) { field in
            PlaceSearchView { place in
                if field == .from { from = place } else { to = place }
                picking = nil
                rebuild()
            }
            .presentationBackground(Color.night)
        }
    }

    private func fieldRow(title: String, place: Place?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.gold.opacity(0.85))
                Text(place?.name ?? String(localized: "Выбрать"))
                    .font(.display(20, weight: .regular))
                    .foregroundStyle(place == nil ? Color.ash : Color.parchment)
                if let place {
                    Text(place.regionName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ash)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.trailing, 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summary(built: CustomRoute, route: Route) -> some View {
        // Примерно 8 000 шагов в день по 0,7 м плюс полкилометра, которые путник проходит сам.
        let perDay = 8_000 * 0.7 / 1000 + GameEngine.passiveKmPerDay
        let days = Int((built.totalKm / perDay).rounded(.up))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.km(built.totalKm))
                    .font(.display(34, weight: .regular))
                    .foregroundStyle(Color.gold)
                Text("км по дорогам")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ash)
            }
            Text("Стоянок: \(route.stops.count) · испытаний: \(route.events.count)")
                .font(.system(size: 13))
                .foregroundStyle(Color.parchment)
            Text("Около \(Fmt.days(days)) при 8 000 шагов в день")
                .font(.system(size: 12))
                .foregroundStyle(Color.ash)
        }
    }

    private func useMyLocation() {
        weather.requestPermission {
            Task { @MainActor in
                // Координата появится после первого ответа геолокации.
                for _ in 0..<20 {
                    if let loc = weather.location {
                        let point = GeoPoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                        from = PlaceStore.shared.nearest(to: point, maxRank: 4)
                        rebuild()
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
    }

    private func rebuild() {
        built = nil
        preview = nil
        failed = false
        guard let from, let to, from.id != to.id else { return }
        building = true
        let a = from, b = to
        Task.detached(priority: .userInitiated) {
            let route = RouteBuilder.build(from: a, to: b)
            let shown = route.map { RouteBuilder.makeRoute($0) }
            await MainActor.run {
                building = false
                built = route
                preview = shown
                failed = route == nil
            }
        }
    }
}

/// Поиск населённого пункта по-русски или по-казахски.
struct PlaceSearchView: View {
    let onPick: (Place) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PlaceStore.shared.search(query)) { place in
                Button {
                    onPick(place)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.display(17, weight: .regular))
                            .foregroundStyle(Color.parchment)
                        HStack(spacing: 6) {
                            Text(place.regionName)
                            if place.pop >= 1000 {
                                Text("· \(place.pop.formatted()) жителей")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ash)
                    }
                }
                .listRowBackground(Color.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Color.night.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Город или село"))
            .navigationTitle("Населённый пункт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
