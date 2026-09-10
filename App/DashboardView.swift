import SwiftUI

// MARK: - Building blocks

/// One window (session or weekly) inside a provider card.
struct WindowPanel: View {
    let title: String
    let usedSuffix: String
    let window: UsageWindow?
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("Remaining")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window == nil ? Color.secondary : tint)

                SegmentedBar(remaining: window?.remainingPercent ?? 0, tint: tint)
                    .frame(height: 9)

                Text(window.map { "~ \(Int($0.usedPercent.rounded()))% used \(usedSuffix)" }
                     ?? "no data yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            RingGauge(remaining: window?.remainingPercent ?? 0, tint: tint)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

/// A provider's whole card: identity, status, and both windows.
struct DashboardProviderCard: View {
    let usage: ProviderUsage

    private var tint: Color { usage.provider.accent }

    private var subtitle: String {
        switch usage.provider {
        case .claude: return "Your AI coding partner"
        case .codex: return "Your coding agent"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProviderLogo(provider: usage.provider, size: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.provider.displayName)
                        .font(.system(size: 24, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                StatusBadge(usage: usage)
            }

            WindowPanel(title: "Session", usedSuffix: "this session",
                        window: usage.session, tint: tint)
            WindowPanel(title: "Weekly", usedSuffix: "this week",
                        window: usage.weekly, tint: tint)
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

/// Green when the last refresh worked, amber with the reason when it did not.
struct StatusBadge: View {
    let usage: ProviderUsage

    var body: some View {
        let ok = usage.error == nil
        HStack(spacing: 5) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(ok ? "Online" : (usage.error ?? "Error"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? Color.primary : Color.orange)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((ok ? Color.green : Color.orange).opacity(0.13), in: Capsule())
        .help(usage.error ?? "Last refresh succeeded")
    }
}

// MARK: - Next reset

/// Which allowance rolls over next, and how long that is.
struct NextResetPanel: View {
    let snapshot: UsageSnapshot

    private struct Upcoming {
        let provider: ProviderUsage.Provider
        let date: Date
    }

    private var upcoming: [Upcoming] {
        snapshot.providers.flatMap { usage -> [Upcoming] in
            [usage.session, usage.weekly]
                .compactMap { $0?.resetsAt }
                .map { Upcoming(provider: usage.provider, date: $0) }
        }
        .filter { $0.date > Date() }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next reset")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Which allowance resets next?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("All times in your local timezone")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if upcoming.isEmpty {
                Text("No upcoming resets — every window is already full.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 3) {
                            Rectangle()
                                .fill(item.provider.accent)
                                .frame(width: 26, height: 3)
                                .clipShape(Capsule())
                            Text(item.provider.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.provider.accent)
                            Text(item.date, format: .relative(presentation: .numeric))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text(item.date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var model: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                ForEach(model.snapshot.providers, id: \.provider) { usage in
                    DashboardProviderCard(usage: usage)
                        .frame(maxWidth: .infinity)
                }
            }

            NextResetPanel(snapshot: model.snapshot)
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(ProviderUsage.Provider.claude.accent)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 1) {
                Text("VibeWidget")
                    .font(.system(size: 21, weight: .bold))
                Text("Usage at a glance. Keep building.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 1) {
                Text("Last updated")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(model.snapshot.hasData
                     ? model.snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened)
                     : "never")
                    .font(.system(size: 11, weight: .medium))
            }

            Button {
                Task { await model.refresh() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(model.isRefreshing)
            .help("Refresh now")

            Button("Sync now") { Task { await model.refresh() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)

            Button("Preferences…") { openWindow(id: VibeWidgetApp.settingsWindowID) }
        }
    }
}
