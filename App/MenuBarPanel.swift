import SwiftUI

/// One tappable row in the panel's action list.
///
/// A window-style MenuBarExtra draws plain SwiftUI, so the hover highlight and
/// the shortcut hint that a real menu would supply have to be built by hand.
private struct MenuActionRow: View {
    let icon: String
    let title: String
    var shortcut: String?
    /// The key that actually triggers the row. A window-style panel does not
    /// bind shortcuts the way a real menu does, so without this the hint text
    /// on the right would be decoration.
    var key: KeyEquivalent?
    /// The panel's primary destination. It leads through weight and the
    /// provider accent rather than through a filled bar, which at 340pt wide
    /// outweighed the quota figures the panel exists to show.
    var prominent = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: LayoutSpacing.compact) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: prominent ? .semibold : .regular))
                    .frame(width: 20)
                    .foregroundStyle(prominent
                                     ? AnyShapeStyle(ProviderUsage.Provider.claude.accent)
                                     : AnyShapeStyle(.primary))
                Text(title)
                    .font(.system(size: 13, weight: prominent ? .semibold : .regular))
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, LayoutSpacing.compact)
            .padding(.vertical, LayoutSpacing.tight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.09)
                          : (prominent ? Color.primary.opacity(0.05) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .ifLet(key) { view, key in view.keyboardShortcut(key, modifiers: .command) }
    }
}

private extension View {
    /// Applies a modifier only when the value is present, so rows without a
    /// shortcut do not register one.
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?,
                                 transform: (Self, T) -> Content) -> some View {
        if let value { transform(self, value) } else { self }
    }
}

/// One provider's session line: identity, percentage, bar, and reset time.
private struct PanelProviderRow: View {
    let usage: ProviderUsage

    private var window: UsageWindow? { usage.session }

    var body: some View {
        HStack(alignment: .top, spacing: LayoutSpacing.compact) {
            ProviderLogo(provider: usage.provider, size: 34)

            VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Text(usage.provider.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(usageValueTint(for: window))
                }

                SegmentedBar(remaining: window?.remainingPercent ?? 0,
                             tint: usageTint(for: window, accent: usage.provider.accent), segments: 8)
                .frame(height: 6)

                // Always present, so both providers occupy the same height.
                // Letting it disappear when a provider has no reset time left
                // the two rows visibly unequal.
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(footnoteIsError ? AnyShapeStyle(Color.orange)
                                                     : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(usage.error ?? footnote)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(usage.provider.displayName), \(window.map { "\(Int($0.remainingPercent.rounded())) percent remaining" } ?? "no usage data"). \(footnote)")
    }

    /// The line under the bar.
    ///
    /// Errors take precedence because a carried-forward number must not look
    /// current. The percentage remains visible as the last known value.
    private var footnote: String {
        if let error = usage.error {
            return window == nil ? error : "Last value · \(error)"
        }
        if let text = resetText { return text }
        guard let window else { return "No data yet" }
        return window.remainingPercent >= 100 ? "Not started" : "Reset time unknown"
    }

    /// Amber only when the error is all we have.
    private var footnoteIsError: Bool { usage.error != nil }

    /// Mirrors the widget's wording so the two never describe the same window
    /// differently.
    private var resetText: String? {
        guard let date = window?.resetsAt, date > Date() else { return nil }
        if date.timeIntervalSinceNow < 12 * 3600 {
            let minutes = Int(date.timeIntervalSinceNow / 60)
            let hours = minutes / 60
            return hours > 0 ? "Resets in \(hours)h \(minutes % 60)m"
                             : "Resets in \(minutes)m"
        }
        return "Resets at \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct MenuBarPanel: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject private var updater = UpdateChecker.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator

            Text("5-hour limit remaining")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, LayoutSpacing.standard)
                .padding(.top, LayoutSpacing.compact)
                .padding(.bottom, LayoutSpacing.tight)

            VStack(spacing: 0) {
                PanelProviderRow(usage: model.snapshot.claude)
                    .padding(.horizontal, LayoutSpacing.standard)
                    .padding(.bottom, LayoutSpacing.compact)
                Divider().padding(.horizontal, LayoutSpacing.standard)
                PanelProviderRow(usage: model.snapshot.codex)
                    .padding(.horizontal, LayoutSpacing.standard)
                    .padding(.top, LayoutSpacing.compact)
            }
            // The removed "Next reset" row used to supply this gap.
            .padding(.bottom, LayoutSpacing.compact)

            separator
            actions
        }
        .frame(width: 340)
        .padding(.vertical, LayoutSpacing.tight)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: LayoutSpacing.compact) {
            Image(nsImage: MenuBarGauge.image(claude: model.remaining(for: .claude),
                                              chatgpt: model.remaining(for: .codex),
                                              side: 34))
            // No app name: this panel only ever opens from VibeWidget's own
            // menu bar item, so the title was a label on the obvious.
            HStack(spacing: LayoutSpacing.tight) {
                Circle()
                    .fill(model.snapshot.providers.contains { $0.error != nil }
                          ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(updatedText)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            refreshButton
        }
        .padding(.horizontal, LayoutSpacing.standard)
        .padding(.bottom, LayoutSpacing.compact)
    }

    private var updatedText: String {
        guard model.snapshot.hasData else {
            return model.isRefreshing ? "Fetching usage…" : "No usage data yet"
        }
        let age = Date().timeIntervalSince(model.snapshot.capturedAt)
        // The dot beside this line already carries the amber warning, and
        // appending the words to it only truncated the timestamp in a 340pt
        // panel.
        return age < 60
            ? "Updated now"
            : "Updated \(model.snapshot.capturedAt.formatted(.relative(presentation: .numeric)))"
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Group {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.primary.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing)
        .help("Refresh now")
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityLabel(model.isRefreshing ? "Refreshing usage" : "Refresh usage")
    }

    // MARK: Sections

    private var separator: some View {
        Divider().padding(.horizontal, LayoutSpacing.standard)
    }


    /// Absent unless there is something to act on, so the panel does not carry
    /// a permanent row saying nothing. Installing is always a click: an app
    /// that replaces itself while someone is away is an app they cannot
    /// choose to keep as it is.
    @ViewBuilder
    private var updateRow: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .available(let version):
            MenuActionRow(icon: "arrow.down.circle", title: "Update to \(version)") {
                updater.install()
            }
        case .installing:
            MenuActionRow(icon: "arrow.triangle.2.circlepath", title: "Updating…") {}
                .disabled(true)
        case .failed(let reason):
            MenuActionRow(icon: "exclamationmark.triangle", title: "Update failed — try again") {
                updater.install()
            }
            .help(reason)
        }
    }

    private var actions: some View {
        VStack(spacing: 2) {
            updateRow

            MenuActionRow(icon: "arrow.up.forward.square", title: "Open Dashboard",
                          shortcut: "⌘ D", key: "d", prominent: true) {
                open(VibeWidgetApp.dashboardWindowID)
            }

            MenuActionRow(icon: "gearshape", title: "Settings…", shortcut: "⌘ ,", key: ",") {
                open(VibeWidgetApp.settingsWindowID)
            }

            Divider().padding(.horizontal, LayoutSpacing.standard)
                .padding(.vertical, LayoutSpacing.tight)

            MenuActionRow(icon: "power", title: "Quit VibeWidget", shortcut: "⌘ Q", key: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, LayoutSpacing.micro)
        .padding(.top, LayoutSpacing.tight)
    }

    /// A menu bar app is not frontmost when its panel is open, so the window
    /// would otherwise appear behind whatever the user was looking at.
    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
