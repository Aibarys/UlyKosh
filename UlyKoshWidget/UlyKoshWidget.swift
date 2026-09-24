import SwiftUI
import WidgetKit

struct KmProvider: TimelineProvider {
    func placeholder(in context: Context) -> KmEntry {
        KmEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (KmEntry) -> Void) {
        completion(KmEntry(date: .now, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KmEntry>) -> Void) {
        let entry = KmEntry(date: .now, snapshot: WidgetSnapshot.load())
        // Приложение само перезагружает виджет после синхронизации; это запасной интервал.
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(30 * 60))))
    }
}

@main
struct UlyKoshWidgetBundle: WidgetBundle {
    var body: some Widget {
        UlyKoshWidget()
    }
}

struct UlyKoshWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UlyKoshKm", provider: KmProvider()) { entry in
            WidgetRootView(entry: entry)
                .containerBackground(for: .widget) { Color.night }
        }
        .configurationDisplayName("Километры дня")
        .description("Сколько аул прошёл сегодня и к какой стоянке идёт.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
