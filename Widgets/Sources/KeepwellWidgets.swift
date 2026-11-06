import DesignSystem
import SwiftUI
import WidgetKit

@main
struct KeepwellWidgetsBundle: WidgetBundle {
    init() {
        KWFonts.register()
    }

    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.keepwell.placeholder", provider: PlaceholderProvider()) { _ in
            Text(verbatim: "Keepwell")
                .kwTextStyle(.heading)
                .foregroundStyle(KWColor.Text.primary)
                .containerBackground(KWColor.Surface.bg, for: .widget)
        }
        .configurationDisplayName("Keepwell")
        .description("Example widget.")
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in _: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in _: Context, completion: @escaping @Sendable (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}
