import SwiftUI

// MARK: - Usage building blocks

/// One allowance inside a provider card. The percentage is the dominant fact;
/// the segmented bar is its single supporting visual encoding.
struct WindowPanel: View {
    let title: String
    /// Only for an allowance whose name does not explain itself. "5-hour" and
    /// "Weekly" already did, and their captions only restated them.
    var detail: String?
    let window: UsageWindow?
    let tint: Color

    private var percentage: String {
        window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
    }

    private var resetText: String {
        guard let date = window?.resetsAt else { return "Reset time unavailable" }
        guard date > Date() else { return "Reset time passed · Refresh needed" }
        return "Resets \(date.formatted(.relative(presentation: .numeric)))"
    }

    private var barTint: Color { usageTint(for: window, accent: tint) }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: LayoutSpacing.compact) {
                VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
                    Text(title)
                        .font(.headline)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: LayoutSpacing.compact)

                Text(percentage)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(usageValueTint(for: window))
            }

            SegmentedBar(remaining: window?.remainingPercent ?? 0, tint: barTint)
                .frame(height: 8)

            Text(window == nil ? "No usage data yet" : resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(percentage) remaining. \(window == nil ? "No usage data yet" : resetText)")
    }
}

/// A provider's complete status, kept on one surface rather than nesting a card
/// around a second set of cards.
struct DashboardProviderCard: View {
    let usage: ProviderUsage

    private var tint: Color { usage.provider.accent }

    private var limits: [(title: String, window: UsageWindow?)] {
        [("5-hour", usage.session), ("Weekly", usage.weekly)]
    }

    private var hasData: Bool {
        usage.session != nil || usage.weekly != nil || usage.modelScoped != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.standard) {
            HStack(spacing: LayoutSpacing.compact) {
                ProviderLogo(provider: usage.provider, size: 34)
                Text(usage.provider.displayName)
                    .font(.title2.weight(.bold))
                Spacer(minLength: LayoutSpacing.compact)
            }

            // A pill reading "Needs attention" above a line naming the actual
            // problem said the same thing twice, and its healthy counterpart
            // said nothing the figures below did not already say.
            if let error = usage.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(usage.provider.displayName) needs attention. \(error)")
            } else if !hasData {
                Label("Waiting for usage data", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(Array(limits.enumerated()), id: \.offset) { index, limit in
                if index > 0 { Divider() }
                WindowPanel(title: limit.title, window: limit.window, tint: tint)
            }

            if let scoped = usage.modelScoped {
                Divider()
                supplementalLimit(scoped)
            }
        }
        .padding(LayoutSpacing.standard)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func supplementalLimit(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: LayoutSpacing.tight) {
                VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
                    Text(usage.modelScopedName ?? "Model")
                        .font(.subheadline.weight(.semibold))
                    Text("Model-specific weekly allowance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: LayoutSpacing.compact)
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(usageValueTint(for: window))
            }
            SegmentedBar(remaining: window.remainingPercent,
                         tint: usageTint(for: window, accent: tint), segments: 8)
                .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(usage.modelScopedName ?? "Model"), \(Int(window.remainingPercent.rounded())) percent remaining")
    }
}

/// The dashboard's first answer: the allowance most likely to stop work.
struct LimitingAllowancePanel: View {
    let snapshot: UsageSnapshot

    private struct Item {
        let provider: ProviderUsage.Provider
        let label: String
        let window: UsageWindow
    }

    private var limiting: Item? {
        snapshot.providers.flatMap { usage -> [Item] in
            var windows: [(String, UsageWindow?)] = [
                ("5-hour", usage.session),
                ("Weekly", usage.weekly),
            ]
            if usage.modelScoped != nil {
                windows.append((usage.modelScopedName ?? "Model", usage.modelScoped))
            }
            return windows.compactMap { label, window in
                window.map { Item(provider: usage.provider, label: label, window: $0) }
            }
        }
        .min { $0.window.remainingPercent < $1.window.remainingPercent }
    }

    var body: some View {
        if let limiting {
            VStack(alignment: .leading, spacing: LayoutSpacing.compact) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LayoutSpacing.compact) {
                        identity(limiting)
                        Spacer(minLength: LayoutSpacing.standard)
                        reset(limiting.window)
                        percentage(limiting)
                    }

                    VStack(alignment: .leading, spacing: LayoutSpacing.compact) {
                        HStack(spacing: LayoutSpacing.compact) {
                            identity(limiting)
                            Spacer(minLength: LayoutSpacing.tight)
                            percentage(limiting)
                        }
                        reset(limiting.window)
                    }
                }
                // No bar here: this same allowance is drawn with one inside its
                // provider card a few hundred points below.
            }
            .padding(LayoutSpacing.standard)
            .background(limiting.provider.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }

    private func identity(_ item: Item) -> some View {
        HStack(spacing: LayoutSpacing.tight) {
            ProviderLogo(provider: item.provider, size: 28)
            VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
                Text("\(item.provider.displayName) · \(item.label)")
                    .font(.headline)
                Text("Most constrained allowance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentage(_ item: Item) -> some View {
        Text("\(Int(item.window.remainingPercent.rounded()))%")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(usageValueTint(for: item.window))
    }

    /// Carries the clock time too, which is what the separate "Next reset" row
    /// used to be for.
    private func reset(_ window: UsageWindow) -> some View {
        Group {
            if let date = window.resetsAt, date > Date() {
                Label("Resets \(date.formatted(.relative(presentation: .numeric))) · \(date.formatted(date: .omitted, time: .shortened))",
                      systemImage: "clock")
            } else {
                Label("Reset time unavailable", systemImage: "clock.badge.questionmark")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var model: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutSpacing.section) {
                header

                if model.snapshot.hasData {
                    LimitingAllowancePanel(snapshot: model.snapshot)
                    providerLayout
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: 1120)
            .padding(LayoutSpacing.page)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Claude can carry a third allowance and an error line that ChatGPT does
    /// not, so side-by-side cards are only equivalent if they are also the same
    /// height. A `Grid` row sizes itself to its tallest cell and then offers
    /// that height to the others; an `HStack` inside a scroll view has no
    /// bounded height to share, so `maxHeight: .infinity` there does nothing.
    private var providerLayout: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: LayoutSpacing.standard, verticalSpacing: 0) {
                GridRow {
                    providerCards(minWidth: 360, equalHeight: true)
                }
            }

            VStack(spacing: LayoutSpacing.standard) {
                providerCards(minWidth: nil, equalHeight: false)
            }
            // Stacked cards would otherwise inherit the whole window width, and
            // a 700pt row leaves the label and its percentage at opposite ends
            // of the screen. Capping the column keeps both branches reading the
            // same way.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func providerCards(minWidth: CGFloat?, equalHeight: Bool) -> some View {
        ForEach(model.snapshot.providers, id: \.provider) { usage in
            DashboardProviderCard(usage: usage)
                .frame(minWidth: minWidth, maxWidth: .infinity,
                       maxHeight: equalHeight ? .infinity : nil, alignment: .top)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: LayoutSpacing.standard) {
                titleBlock
                Spacer(minLength: LayoutSpacing.section)
                freshness(.trailing)
                actions
            }

            VStack(alignment: .leading, spacing: LayoutSpacing.compact) {
                titleBlock
                HStack(spacing: LayoutSpacing.compact) {
                    // Right-aligned under a left-aligned title reads as a
                    // mistake once the header stacks.
                    freshness(.leading)
                    Spacer(minLength: LayoutSpacing.tight)
                    actions
                }
            }
        }
    }

    private var titleBlock: some View {
        HStack(spacing: LayoutSpacing.compact) {
            Image(nsImage: MenuBarGauge.image(claude: model.remaining(for: .claude),
                                              chatgpt: model.remaining(for: .codex),
                                              side: 42))
                .accessibilityHidden(true)

            // The subtitle described exactly what the two provider cards below
            // already show.
            Text("Usage")
                .font(.title2.weight(.bold))
        }
    }

    private func freshness(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: LayoutSpacing.micro) {
            Text("Last updated")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.snapshot.hasData
                 ? model.snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened)
                 : "Not yet")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: LayoutSpacing.tight) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label(model.isRefreshing ? "Refreshing…" : "Refresh",
                      systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityHint("Fetch the latest Claude and ChatGPT usage")

            Button {
                openWindow(id: VibeWidgetApp.settingsWindowID)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LayoutSpacing.compact) {
            Image(systemName: model.isRefreshing ? "arrow.clockwise" : "chart.bar.xaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.isRefreshing ? "Fetching usage…" : "No usage data yet")
                .font(.title3.weight(.semibold))
            Text("Refresh after using Claude Code or Codex CLI so VibeWidget can read their latest allowance data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if !model.isRefreshing {
                Button("Refresh Usage") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(LayoutSpacing.page)
        .accessibilityElement(children: .contain)
    }
}
