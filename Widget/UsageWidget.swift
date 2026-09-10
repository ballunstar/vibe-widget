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

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var prefs: AppSettings.WidgetPreferences { .current }

    var body: some View {
        content
            .padding(family == .systemLarge ? 8 : 16)
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
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entry.snapshot.providers, id: \.provider) { usage in
                let window = tightest(usage)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        ProviderLogo(provider: usage.provider, size: 13)
                        Text(usage.provider.displayName)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(percentText(window, compact: prefs.compactNumbers))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(usage.provider.accent)
                    }
                    SegmentedBar(remaining: window?.remainingPercent ?? 0,
                                 tint: usage.provider.accent, segments: 6)
                        .frame(height: 6)
                    if prefs.showResetTime, let label = ResetLabel.text(for: window) {
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Medium (wide)

    /// Two compact provider surfaces. Each allowance keeps its label, value,
    /// and bar together so the wide layout can be understood at a glance.
    private var medium: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(entry.snapshot.providers, id: \.provider) { usage in
                mediumColumn(usage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(10)
                    .background(usage.provider.accent.opacity(0.075),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func mediumColumn(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ProviderLogo(provider: usage.provider, size: 21)
                Text(usage.provider.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(mainWindows(usage), id: \.label) { column in
                    mediumWindow(column.label, column.window, usage.provider.accent)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let scoped = usage.modelScoped {
                    Text(usage.modelScopedName ?? "Model")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(percentText(scoped, compact: prefs.compactNumbers))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(usage.provider.accent)
                }

                Spacer(minLength: 0)

                if prefs.showResetTime, let parts = ResetLabel.parts(for: nextReset(usage)) {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(parts.value)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
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
                .foregroundStyle(tint)
            SegmentedBar(remaining: window?.remainingPercent ?? 0,
                         tint: tint, segments: 5)
                .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Large (tall)

    /// Providers stack vertically in the square family. Each section gets the
    /// same height while Session and Weekly remain easy to compare side by side.
    private var large: some View {
        VStack(spacing: 10) {
            ForEach(entry.snapshot.providers, id: \.provider) { usage in
                largeSection(usage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(usage.provider.accent.opacity(0.075),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func largeSection(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
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
                            .foregroundStyle(usage.provider.accent)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                ForEach(mainWindows(usage), id: \.label) { column in
                    largeWindow(column.label, column.window, usage.provider.accent)
                }
            }

            Spacer(minLength: 0)

            if let scoped = usage.modelScoped {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(usage.modelScopedName ?? "Model")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(percentText(scoped, compact: prefs.compactNumbers))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(usage.provider.accent)
                        Spacer(minLength: 0)
                    }
                    SegmentedBar(remaining: scoped.remainingPercent,
                                 tint: usage.provider.accent, segments: 7)
                        .frame(height: 7)
                }
            }
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
                .foregroundStyle(tint)
            SegmentedBar(remaining: window?.remainingPercent ?? 0, tint: tint, segments: 7)
                .frame(height: 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    /// The two headline windows every provider has.
    private func mainWindows(_ usage: ProviderUsage) -> [(label: String, window: UsageWindow?)] {
        [("Session", usage.session), ("Weekly", usage.weekly)]
    }


    private func tightest(_ usage: ProviderUsage) -> UsageWindow? {
        [usage.session, usage.weekly].compactMap { $0 }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    /// Whichever of the two windows rolls over soonest.
    private func nextReset(_ usage: ProviderUsage) -> UsageWindow? {
        [usage.session, usage.weekly]
            .compactMap { $0 }
            .filter { ($0.resetsAt ?? .distantPast) > Date() }
            .min { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VibeUsageWidget", provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI Usage")
        .description("How much Claude and ChatGPT usage you have left.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct VibeWidgetBundle: WidgetBundle {
    var body: some Widget { UsageWidget() }
}
