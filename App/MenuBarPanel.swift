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
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.09) : .clear)
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
        HStack(alignment: .top, spacing: 14) {
            ProviderLogo(provider: usage.provider, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(usage.provider.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(usage.provider.accent)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(usage.provider.accent)
                            .frame(width: geo.size.width * (window?.remainingPercent ?? 0) / 100)
                    }
                }
                .frame(height: 6)

                // Always present, so both providers occupy the same height.
                // Letting it disappear when a provider has no reset time left
                // the two rows visibly unequal.
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(footnoteIsError ? AnyShapeStyle(Color.orange)
                                                     : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
    }

    /// The line under the bar.
    ///
    /// The reset time wins over an error whenever there is still a figure to
    /// show: a failed refresh carries the previous reading forward, so the
    /// countdown remains the more useful thing to read. Staleness is already
    /// signalled by the header's dot and "Updated …" line, and a transient 429
    /// should not blank out data that is still broadly right. The error only
    /// takes the line when there is nothing else to say.
    private var footnote: String {
        if let text = resetText { return text }
        if let error = usage.error { return error }
        guard let window else { return "No data yet" }
        return window.remainingPercent >= 100 ? "Not started" : "Reset time unknown"
    }

    /// Amber only when the error is all we have.
    private var footnoteIsError: Bool { resetText == nil && usage.error != nil }

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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator

            Text("Session Remaining")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                PanelProviderRow(usage: model.snapshot.claude)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                Divider().padding(.horizontal, 16)
                PanelProviderRow(usage: model.snapshot.codex)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            // The removed "Next reset" row used to supply this gap.
            .padding(.bottom, 14)

            separator
            actions
        }
        .frame(width: 340)
        .padding(.vertical, 10)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: MenuBarGauge.image(claude: model.remaining(for: .claude),
                                              chatgpt: model.remaining(for: .codex),
                                              side: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text("VibeWidget")
                    .font(.system(size: 17, weight: .bold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.snapshot.providers.contains { $0.error != nil }
                              ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text(updatedText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            refreshButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var updatedText: String {
        guard model.snapshot.hasData else { return "No data yet" }
        let age = Date().timeIntervalSince(model.snapshot.capturedAt)
        if age < 60 { return "Updated now" }
        return "Updated \(model.snapshot.capturedAt.formatted(.relative(presentation: .numeric)))"
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
    }

    // MARK: Sections

    private var separator: some View {
        Divider().padding(.horizontal, 16)
    }


    private var actions: some View {
        VStack(spacing: 2) {
            MenuActionRow(icon: "arrow.up.forward.square", title: "Open Dashboard",
                          shortcut: "⌘ D", key: "d") {
                open(VibeWidgetApp.dashboardWindowID)
            }
            MenuActionRow(icon: "gearshape", title: "Settings…", shortcut: "⌘ ,", key: ",") {
                open(VibeWidgetApp.settingsWindowID)
            }
            MenuActionRow(icon: "arrow.triangle.2.circlepath",
                          title: model.isRefreshing ? "Refreshing…" : "Refresh Now") {
                Task { await model.refresh() }
            }

            Divider().padding(.horizontal, 16).padding(.vertical, 6)

            MenuActionRow(icon: "power", title: "Quit VibeWidget", shortcut: "⌘ Q", key: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    /// A menu bar app is not frontmost when its panel is open, so the window
    /// would otherwise appear behind whatever the user was looking at.
    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
