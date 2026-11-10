import Core
import DesignSystem
import SwiftUI
import WidgetKit

@main
struct KeepwellWidgetsBundle: WidgetBundle {
    init() {
        KWFonts.register()
    }

    var body: some Widget {
        MonthWidget()
        QuickLogWidget()
        NetWorthWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// `nil` until the app has opened once and written it.
    let snapshot: WidgetSnapshot?
}

/// Reads what the app last wrote. The app reloads the timelines whenever its data changes, so the
/// widget never computes anything itself.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        let stored = WidgetSnapshotStore().load()
        completion(SnapshotEntry(date: .now, snapshot: stored ?? (context.isPreview ? .preview : nil)))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore().load())], policy: .never))
    }
}

/// Shown before the app has written anything.
struct OpenAppPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWLogoMark(size: 28)
                .foregroundStyle(KWColor.Semantic.logo)
            Text("Open Keepwell to see your month here.")
                .font(.kw(13, weight: 600, relativeTo: .footnote))
                .foregroundStyle(KWColor.Text.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - This month

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.keepwell.month", provider: SnapshotProvider()) { entry in
            MonthWidgetView(snapshot: entry.snapshot)
                .containerBackground(KWColor.Surface.surface, for: .widget)
                .widgetURL(AppLink.home)
        }
        .configurationDisplayName("This month")
        .description("What you've spent this month and your drafts.")
        .supportedFamilies([.systemSmall])
    }
}

struct MonthWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading) {
                Text(snapshot.monthTitle)
                    .font(.kw(12, weight: 600, relativeTo: .caption))
                    .foregroundStyle(KWColor.Text.muted)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.spent)
                        .font(.kw(26, weight: 800, relativeTo: .title2))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                    Text(snapshot.spentCaption)
                        .font(.kw(12, weight: 500, relativeTo: .caption))
                        .foregroundStyle(KWColor.Text.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                KWProgressBar(max(snapshot.spentFraction, 0.04), fill: KWColor.Brand.accent)
            }
            .foregroundStyle(KWColor.Text.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            OpenAppPrompt()
        }
    }
}

// MARK: - Log quickly

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.keepwell.quicklog", provider: SnapshotProvider()) { entry in
            QuickLogWidgetView(snapshot: entry.snapshot)
                .containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Log quickly")
        .description("One tap to log an expense in your usual categories.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickLogWidgetView: View {
    let snapshot: WidgetSnapshot?

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading) {
            Text(snapshot?.shortcutsTitle ?? String(localized: "Log quickly"))
                .font(.kw(12, weight: 700, relativeTo: .caption))
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(snapshot?.shortcuts.prefix(3) ?? [], id: \.categoryID) { shortcut in
                    Button(intent: QuickLogIntent(categoryID: shortcut.categoryID)) {
                        Text(shortcut.title)
                            .font(.kw(12, weight: 700, relativeTo: .caption))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(KWColor.Surface.light, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button(intent: QuickLogIntent(categoryID: nil)) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("New expense"))
            }
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Net worth

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.keepwell.networth", provider: SnapshotProvider()) { entry in
            NetWorthWidgetView(snapshot: entry.snapshot)
                .containerBackground(KWColor.Surface.surface, for: .widget)
                .widgetURL(AppLink.home)
        }
        .configurationDisplayName("Net worth")
        .description("Everything you have in your main currency, with your largest balances.")
        .supportedFamilies([.systemMedium])
    }
}

struct NetWorthWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.netWorthTitle)
                        .font(.kw(12, weight: 600, relativeTo: .caption))
                        .foregroundStyle(KWColor.Text.muted)
                    Text(snapshot.netWorth)
                        .font(.kw(26, weight: 800, relativeTo: .title2))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                    if let caption = snapshot.netWorthCaption {
                        Text(caption)
                            .font(.kw(12, weight: 600, relativeTo: .caption))
                            .foregroundStyle(KWColor.State.positive)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.balances, id: \.title) { line in
                        Text(verbatim: "\(line.title) \(line.value)")
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                .font(.kw(12, weight: 500, relativeTo: .caption))
                .foregroundStyle(KWColor.Text.secondary)
                .monospacedDigit()
            }
            .foregroundStyle(KWColor.Text.primary)
        } else {
            OpenAppPrompt()
        }
    }
}

// MARK: - Preview data

extension WidgetSnapshot {
    /// What the widget gallery shows before any data exists: made-up amounts in the person's language.
    static var preview: WidgetSnapshot {
        let month = Date.now.formatted(.dateTime.month(.wide)).localizedCapitalized
        return WidgetSnapshot(
            monthTitle: month,
            spent: "$709.58",
            spentCaption: String(localized: "spent · 4 drafts"),
            spentFraction: 0.29,
            netWorthTitle: String(localized: "Net worth"),
            netWorth: "$11,157.46",
            netWorthCaption: String(localized: "\(month): you saved 71%"),
            balances: [
                .init(title: String(localized: "Bank"), value: "$9,306"),
                .init(title: String(localized: "Cash"), value: "C$8,420"),
            ],
            shortcutsTitle: String(localized: "Log quickly"),
            shortcuts: [
                .init(categoryID: "restaurants", title: String(localized: "Restaurants")),
                .init(categoryID: "transport", title: String(localized: "Transport")),
                .init(categoryID: "groceries", title: String(localized: "Groceries")),
            ],
            updatedAt: .now,
        )
    }
}
