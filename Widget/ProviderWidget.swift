import WidgetKit
import SwiftUI
import AppIntents

struct ProviderEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let provider: ProviderUsage.Provider
    /// nil when this widget defers to the app-wide weekly preference.
    let weeklyOverride: Bool?
}

/// Same read-only contract as the combined widget: the container app refreshes,
/// this only renders what it last wrote.
struct ProviderTimelineProvider: AppIntentTimelineProvider {
    private static let refreshInterval: TimeInterval = 10 * 60

    func placeholder(in context: Context) -> ProviderEntry {
        ProviderEntry(date: Date(), snapshot: .placeholder, provider: .claude,
                      weeklyOverride: nil)
    }

    func snapshot(for configuration: SelectProviderIntent, in context: Context) async -> ProviderEntry {
        entry(for: configuration, preview: context.isPreview)
    }

    func timeline(for configuration: SelectProviderIntent, in context: Context) async -> Timeline<ProviderEntry> {
        Timeline(entries: [entry(for: configuration, preview: false)],
                 policy: .after(Date().addingTimeInterval(Self.refreshInterval)))
    }

    private func entry(for configuration: SelectProviderIntent, preview: Bool) -> ProviderEntry {
        ProviderEntry(
            date: Date(),
            snapshot: preview ? .placeholder : (UsageStore.loadCached() ?? .empty),
            provider: configuration.provider.provider,
            weeklyOverride: configuration.weekly.override
        )
    }
}

/// A widget showing one service, so two can be placed side by side — one for
/// Claude, one for ChatGPT — instead of sharing a single tile.
struct ProviderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VibeProviderWidget",
                               intent: SelectProviderIntent.self,
                               provider: ProviderTimelineProvider()) { entry in
            UsageWidgetView(
                entry: UsageEntry(date: entry.date, snapshot: entry.snapshot),
                only: entry.provider,
                weeklyOverride: entry.weeklyOverride
            )
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(VibeWidgetURL.dashboard)
        }
        .configurationDisplayName("Single Provider Usage")
        .description("Track Claude or ChatGPT in its own independently configured widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
