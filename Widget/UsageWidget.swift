import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

/// The widget only ever *reads*. Refreshing means reading Claude's token, which
/// means spawning `/usr/bin/security` — the one binary that keychain item's ACL
/// trusts — and an extension is the wrong place to spawn anything. So the
/// container app owns refreshing and this draws whatever it last wrote.
struct UsageTimelineProvider: TimelineProvider {
    /// How often to re-read the cache. The app pushes reloads on refresh via
    /// WidgetCenter, so this is only a safety net for a missed push.
    private static let refreshInterval: TimeInterval = 10 * 60

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    private func currentEntry(preview: Bool) -> UsageEntry {
        if preview { return UsageEntry(date: Date(), snapshot: .placeholder) }
        // No cache means the app has not run yet; the view turns this into a
        // "open VibeWidget" hint rather than showing invented numbers.
        return UsageEntry(date: Date(), snapshot: UsageStore.loadCached() ?? .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(currentEntry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let next = Date().addingTimeInterval(Self.refreshInterval)
        completion(Timeline(entries: [currentEntry(preview: false)], policy: .after(next)))
    }
}

// MARK: - Shared pieces

/// "Resets in 2h 18m" while that is a useful thing to say, "Resets at 5:00 PM"
/// once the countdown is long enough that a clock time reads better.
enum ResetLabel {
    static func text(for window: UsageWindow?) -> String? {
        guard let date = window?.resetsAt, date > Date() else { return nil }
        if date.timeIntervalSinceNow < 12 * 3600 {
            let minutes = Int(date.timeIntervalSinceNow / 60)
            let hours = minutes / 60
            return hours > 0
                ? "Resets in \(hours)h \(minutes % 60)m"
                : "Resets in \(minutes)m"
        }
        return "Resets at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// Split for the large layout, which stacks the caption above the value.
    static func parts(for window: UsageWindow?) -> (caption: String, value: String)? {
        guard let full = text(for: window) else { return nil }
        if full.hasPrefix("Resets in ") {
            return ("Resets in", String(full.dropFirst("Resets in ".count)))
        }
        return ("Resets at", String(full.dropFirst("Resets at ".count)))
    }
}

private func percentText(_ window: UsageWindow?, compact: Bool) -> String {
    guard let window else { return "—" }
    let value = Int(window.remainingPercent.rounded())
    return compact ? "\(value)" : "\(value)%"
}

// MARK: - Views

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: UsageEntry
    /// `\.widgetFamily` is read-only, so previews and snapshot tests cannot set
    /// it. This lets them ask for a specific layout directly.
    var familyOverride: WidgetFamily?
    /// When set, only this provider is drawn. The layouts already size their
    /// columns with `maxWidth: .infinity`, so a single provider simply takes
    /// the whole widget — which is what the configurable single-provider
    /// widget wants.
    var only: ProviderUsage.Provider?
    /// Per-widget answer to "show the weekly window?". nil defers to the
    /// app-wide preference, which is what the non-configurable widget does.
    var weeklyOverride: Bool?

    /// One place decides, so the layouts and the derived figures cannot drift.
    private var showWeekly: Bool { weeklyOverride ?? prefs.showWeekly }

    private var visibleProviders: [ProviderUsage] {
        guard let only else { return entry.snapshot.providers }
        return entry.snapshot.providers.filter { $0.provider == only }
    }

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var prefs: AppSettings.WidgetPreferences { .current }

    var body: some View {
        content
            // The card layouts run to the edge, so their corners land exactly on
            // the widget's own. Small has no card behind it, so its content
            // still needs a margin of its own.
            .padding(family == .systemSmall ? LayoutSpacing.standard : 0)
            .applyAppearance(prefs.appearance)
    }

    @ViewBuilder
    private var content: some View {
        if !entry.snapshot.hasData {
            needsApp
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
    }

    /// The cache is written by the container app, so an empty cache means the
    /// app has not run — say that instead of drawing empty bars.
    private var needsApp: some View {
        VStack(spacing: 6) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Open VibeWidget")
                .font(.system(size: 11, weight: .semibold))
            Text("The app fetches your usage")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Small

    /// No room for four numbers, so each provider gets its tightest window —
    /// the one that will stop you first.
    private var small: some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
            ForEach(visibleProviders, id: \.provider) { usage in
                let limit = tightest(usage)
                VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
                    HStack(spacing: 5) {
                        ProviderLogo(provider: usage.provider, size: 13)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(usage.provider.displayName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(limit?.label ?? "No data")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(percentText(limit?.window, compact: prefs.compactNumbers))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(usageValueTint(for: limit?.window))
                    }
                    SegmentedBar(remaining: limit?.window.remainingPercent ?? 0,
                                 tint: usageTint(for: limit?.window,
                                                 accent: usage.provider.accent), segments: 6)
                        .frame(height: 6)
                    if prefs.showResetTime, let label = ResetLabel.text(for: limit?.window) {
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Medium (wide)

    /// Two compact provider surfaces. Each allowance keeps its label, value,
    /// and bar together so the wide layout can be understood at a glance.
    private var medium: some View {
        HStack(alignment: .top, spacing: LayoutSpacing.tight) {
            ForEach(visibleProviders, id: \.provider) { usage in
                mediumColumn(usage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(LayoutSpacing.standard)
                    // Concentric with the widget's own rounding rather than a
                    // fixed radius: the system decides the outer curve, and
                    // ContainerRelativeShape insets it by our margin.
                    .background(usage.provider.accent.opacity(0.075),
                                in: ContainerRelativeShape())
            }
        }
    }

    private func mediumColumn(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
            HStack(spacing: LayoutSpacing.tight) {
                ProviderLogo(provider: usage.provider, size: 21)
                Text(usage.provider.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: LayoutSpacing.tight) {
                ForEach(mainWindows(usage), id: \.label) { column in
                    mediumWindow(column.label, column.window, usage.provider.accent)
                }
            }

            if showWeekly, let scoped = usage.modelScoped {
                mediumScoped(scoped, usage: usage)
            }

            Spacer(minLength: 0)

            if prefs.showResetTime, let parts = ResetLabel.parts(for: nextReset(usage)) {
                HStack(spacing: LayoutSpacing.micro) {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .medium))
                    Text("\(parts.caption) \(parts.value)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private func mediumScoped(_ window: UsageWindow, usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
            HStack(alignment: .firstTextBaseline, spacing: LayoutSpacing.micro) {
                Text(usage.modelScopedName ?? "Model")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: LayoutSpacing.micro)
                Text(percentText(window, compact: prefs.compactNumbers))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(usageValueTint(for: window))
            }
            SegmentedBar(remaining: window.remainingPercent,
                         tint: usageTint(for: window, accent: usage.provider.accent),
                         segments: 5)
                .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    private func mediumWindow(_ title: String, _ window: UsageWindow?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(percentText(window, compact: prefs.compactNumbers))
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(usageValueTint(for: window))
            SegmentedBar(remaining: window?.remainingPercent ?? 0,
                         tint: usageTint(for: window, accent: tint), segments: 5)
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Large (tall)

    /// Providers stack vertically in the square family. Each section gets the
    /// same height while Session and Weekly remain easy to compare side by side.
    private var large: some View {
        VStack(spacing: LayoutSpacing.tight) {
            ForEach(visibleProviders, id: \.provider) { usage in
                largeSection(usage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, LayoutSpacing.standard)
                    .padding(.vertical, LayoutSpacing.compact)
                    .background(usage.provider.accent.opacity(0.075),
                                in: ContainerRelativeShape())
            }
        }
    }

    private func largeSection(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
            HStack(alignment: .center, spacing: 8) {
                ProviderLogo(provider: usage.provider, size: 22)
                Text(usage.provider.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 8)

                if prefs.showResetTime, let parts = ResetLabel.parts(for: nextReset(usage)) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .medium))
                        Text(parts.caption)
                            .font(.system(size: 8))
                        Text(parts.value)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            HStack(alignment: .top, spacing: LayoutSpacing.compact) {
                ForEach(mainWindows(usage), id: \.label) { column in
                    largeWindow(column.label, column.window, usage.provider.accent)
                }
            }

            // Above the flexible spacer, not below it: a model limit can be the
            // binding constraint, and pinning it to the bottom edge made the
            // tightest number the least visible one in the section.
            if showWeekly, let scoped = usage.modelScoped {
                VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
                    HStack(alignment: .firstTextBaseline, spacing: LayoutSpacing.micro) {
                        Text(usage.modelScopedName ?? "Model")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(percentText(scoped, compact: prefs.compactNumbers))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(usageValueTint(for: scoped))
                        Spacer(minLength: 0)
                    }
                    SegmentedBar(remaining: scoped.remainingPercent,
                                 tint: usageTint(for: scoped, accent: usage.provider.accent), segments: 7)
                        .frame(height: 7)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func largeWindow(_ title: String, _ window: UsageWindow?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(percentText(window, compact: prefs.compactNumbers))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(usageValueTint(for: window))
            SegmentedBar(remaining: window?.remainingPercent ?? 0,
                         tint: usageTint(for: window, accent: tint), segments: 7)
                .frame(height: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    /// The headline windows to show. With the weekly window switched off the
    /// session one is the only entry, and the layouts — which already lay these
    /// out with `maxWidth: .infinity` — give it the whole column.
    private func mainWindows(_ usage: ProviderUsage) -> [(label: String, window: UsageWindow?)] {
        showWeekly
            ? [("5-hour", usage.session), ("Weekly", usage.weekly)]
            : [("5-hour", usage.session)]
    }

    /// Every window currently in play. Switching the weekly window off means
    /// "I only care about the 5-hour one", so it drops out of the derived
    /// figures too — otherwise the small widget and the reset line would keep
    /// quoting a number the setting just hid.
    private func activeWindows(_ usage: ProviderUsage) -> [UsageWindow] {
        allVisibleWindows(usage).map(\.window)
    }

    private func tightest(_ usage: ProviderUsage) -> (label: String, window: UsageWindow)? {
        allVisibleWindows(usage)
            .min { $0.window.remainingPercent < $1.window.remainingPercent }
    }

    private func allVisibleWindows(_ usage: ProviderUsage) -> [(label: String, window: UsageWindow)] {
        var windows = mainWindows(usage)
            .compactMap { item in item.window.map { (item.label, $0) } }
        if showWeekly, let scoped = usage.modelScoped {
            windows.append((usage.modelScopedName ?? "Model", scoped))
        }
        return windows
    }

    /// Whichever window in play rolls over soonest.
    private func nextReset(_ usage: ProviderUsage) -> UsageWindow? {
        activeWindows(usage)
            .filter { ($0.resetsAt ?? .distantPast) > Date() }
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VibeUsageWidget", provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(VibeWidgetURL.dashboard)
        }
        .configurationDisplayName("AI Usage")
        .description("How much Claude and ChatGPT usage you have left.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct VibeWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        ProviderWidget()
    }
}
