import SwiftUI
import ServiceManagement
import WidgetKit

// MARK: - Layout helpers

/// A titled group of rows, matching the boxed sections in the design.
struct SettingsSection<Content: View>: View {
    let title: String
    var emphasized = false
    @ViewBuilder var content: Content

    /// Only a section that draws a container earns an inset of its own.
    /// Without one, an extra 16pt would push every heading and row past the
    /// pane title they are supposed to line up with.
    private var inset: CGFloat { emphasized ? LayoutSpacing.standard : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.top, emphasized ? LayoutSpacing.compact : 0)
                .padding(.bottom, LayoutSpacing.tight)
            Divider()
            content
        }
        .padding(.horizontal, inset)
        .background {
            if emphasized {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.035))
            }
        }
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
    }
}

/// One row: label, optional explanation, and a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: LayoutSpacing.page) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                control
            }

            VStack(alignment: .leading, spacing: LayoutSpacing.tight) {
                label
                // A switch stranded under the left edge of a two-line
                // description reads as a stray control; keep it where the
                // horizontal layout put it.
                control.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, LayoutSpacing.compact)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
            Text(title).font(.body.weight(.medium))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var section: Pane = .general
    @State private var showClearCacheConfirmation = false
    @State private var actionConfirmation: String?

    enum Pane: String, CaseIterable, Identifiable {
        case general, accounts, notifications, appearance, advanced
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .accounts: return "person"
            case .notifications: return "bell"
            case .appearance: return "paintpalette"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail(showsTitle: true).frame(minWidth: 490)
            }

            VStack(spacing: 0) {
                compactNavigation
                Divider()
                // The picker above already names the pane; repeating it as a
                // title stacked "Settings / General / General" down the window.
                detail(showsTitle: false)
            }
        }
        .frame(minWidth: 520, minHeight: 520)
        .alert("Clear cached usage?", isPresented: $showClearCacheConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cache", role: .destructive) { clearCache() }
        } message: {
            Text("VibeWidget will delete its saved snapshot and immediately fetch fresh usage data.")
        }
    }

    private var sidebar: some View {
        // No identity block: the title bar already reads "Settings", and the
        // version sits in the footer.
        VStack(alignment: .leading, spacing: LayoutSpacing.micro) {
            ForEach(Pane.allCases.filter { $0 != .advanced }) { pane in
                paneButton(pane)
            }
            Spacer(minLength: LayoutSpacing.standard)
            Divider()
            paneButton(.advanced)
        }
        .padding(LayoutSpacing.compact)
        .frame(width: 190)
    }

    private var compactNavigation: some View {
        HStack(spacing: LayoutSpacing.compact) {
            Picker("Settings section", selection: $section) {
                ForEach(Pane.allCases) { pane in
                    Label(pane.label, systemImage: pane.icon).tag(pane)
                }
            }
            .labelsHidden()
            .controlSize(.large)
            .frame(width: 200)
            .accessibilityLabel("Settings section")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LayoutSpacing.page)
        .padding(.vertical, LayoutSpacing.compact)
    }

    private func paneButton(_ pane: Pane) -> some View {
        Button {
            section = pane
        } label: {
            HStack(spacing: LayoutSpacing.tight) {
                Image(systemName: pane.icon)
                    .frame(width: 18)
                    .foregroundStyle(section == pane
                                     ? ProviderUsage.Provider.claude.accent
                                     : Color.secondary)
                Text(pane.label).font(.body.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LayoutSpacing.tight)
            .padding(.vertical, LayoutSpacing.tight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(section == pane ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == pane ? .isSelected : [])
    }

    private func detail(showsTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                Text(section.label)
                    .font(.title.weight(.bold))
                    .padding(.horizontal, LayoutSpacing.page)
                    .padding(.vertical, LayoutSpacing.standard)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LayoutSpacing.section) {
                    switch section {
                    case .general: generalPane
                    case .accounts: accountsPane
                    case .notifications: notificationsPane
                    case .appearance: appearancePane
                    case .advanced: advancedPane
                    }
                }
                .padding(.horizontal, LayoutSpacing.page)
                .padding(.top, showsTitle ? 0 : LayoutSpacing.page)
                .padding(.bottom, LayoutSpacing.page)
                .frame(maxWidth: 760, alignment: .leading)
            }

            Divider()
            HStack {
                Text("VibeWidget \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, LayoutSpacing.page)
            .padding(.vertical, LayoutSpacing.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: General

    private var generalPane: some View {
        Group {
            SettingsSection(title: "Refresh") {
                SettingRow(title: "Automatic refresh",
                           subtitle: "Keep your usage data up to date.") {
                    Toggle("", isOn: Binding(
                        get: { settings.automaticRefresh },
                        set: { settings.automaticRefresh = $0; model.rescheduleTimer() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Automatic refresh")
                }
                Divider()
                SettingRow(title: "Refresh interval") {
                    Picker("", selection: Binding(
                        get: { settings.refreshIntervalSeconds },
                        set: { settings.refreshIntervalSeconds = $0; model.rescheduleTimer() }
                    )) {
                        ForEach(AppSettings.refreshChoices, id: \.self) { seconds in
                            Text(AppSettings.refreshLabel(seconds)).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .disabled(!settings.automaticRefresh)
                    .accessibilityLabel("Refresh interval")
                }
                Divider()
                SettingRow(title: "Check for updates",
                           subtitle: "Asks GitHub for the newest release a few times a day. "
                                   + "Installing one is always a deliberate click.") {
                    Toggle("", isOn: Binding(
                        get: { settings.checkForUpdates },
                        set: { settings.checkForUpdates = $0; UpdateChecker.shared.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UpdateChecker.isHomebrewInstall)
                    .accessibilityLabel("Check for updates")
                }
            }

            SettingsSection(title: "Menu Bar") {
                SettingRow(title: "Show VibeWidget in menu bar",
                           subtitle: "When hidden, VibeWidget stays available from the Dock.") {
                    Toggle("", isOn: Binding(
                        get: { settings.showInMenuBar },
                        set: {
                            settings.showInMenuBar = $0
                            AppAccess.apply(menuBarVisible: $0)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Show VibeWidget in menu bar")
                }
                Divider()
                SettingRow(title: "Display") {
                    Picker("", selection: Binding(
                        get: { settings.menuBarDisplay },
                        set: { settings.menuBarDisplay = $0 }
                    )) {
                        ForEach(AppSettings.MenuBarDisplay.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .disabled(!settings.showInMenuBar)
                    .accessibilityLabel("Menu bar display")
                }
            }

            SettingsSection(title: "Widgets") {
                SettingRow(title: "Show weekly usage",
                           subtitle: "Off shows only the 5-hour window. Per-model limits hide with it.") {
                    Toggle("", isOn: Binding(
                        get: { settings.showWeekly },
                        set: { settings.showWeekly = $0; WidgetCenter.shared.reloadAllTimelines() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Show weekly usage")
                }
                Divider()
                SettingRow(title: "Hide percent symbols",
                           subtitle: "Show 72 instead of 72% in widgets to save space.") {
                    Toggle("", isOn: Binding(
                        get: { settings.compactNumbers },
                        set: { settings.compactNumbers = $0; WidgetCenter.shared.reloadAllTimelines() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Hide percent symbols")
                }
                Divider()
                SettingRow(title: "Show reset time",
                           subtitle: "Display when each window resets.") {
                    Toggle("", isOn: Binding(
                        get: { settings.showResetTime },
                        set: { settings.showResetTime = $0; WidgetCenter.shared.reloadAllTimelines() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Show reset time")
                }
            }

            SettingsSection(title: "Launch") {
                SettingRow(title: "Open VibeWidget at login",
                           subtitle: "Start VibeWidget automatically when you log in.") {
                    Toggle("", isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { LoginItem.set($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Open VibeWidget at login")
                }
            }
        }
    }

    // MARK: Accounts

    /// Read-only. Signing in and out belongs to the Claude Code and Codex CLIs;
    /// this only reports what they left on disk.
    private var accountsPane: some View {
        Group {
            ForEach(model.snapshot.providers, id: \.provider) { usage in
                SettingsSection(title: usage.provider.displayName) {
                    SettingRow(title: "Plan") {
                        Text(usage.plan?.uppercased() ?? "unknown")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(usage.provider.accent.opacity(0.16), in: Capsule())
                            .foregroundStyle(usage.provider.accent)
                    }
                    Divider()
                    SettingRow(title: "Status") {
                        Text(statusText(usage))
                            .font(.body)
                            .foregroundStyle(usage.error == nil
                                             ? AnyShapeStyle(.secondary)
                                             : AnyShapeStyle(Color.orange))
                            .multilineTextAlignment(.trailing)
                    }
                    Divider()
                    SettingRow(title: "Source", subtitle: sourceDescription(usage.provider)) {
                        EmptyView()
                    }
                }
            }

            Text("Sign in and out from the Claude Code and Codex CLIs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The row's label already says "Status", so the state is plain text here
    /// rather than a second pill.
    private func statusText(_ usage: ProviderUsage) -> String {
        if let error = usage.error { return error }
        let hasData = usage.session != nil || usage.weekly != nil || usage.modelScoped != nil
        return hasData ? "Ready" : "Waiting for usage data"
    }

    private func sourceDescription(_ provider: ProviderUsage.Provider) -> String {
        switch provider {
        case .claude:
            return "Claude usage API · Credentials managed by Claude Code"
        case .codex:
            return "Codex session logs · ~/.codex/sessions"
        }
    }

    // MARK: Notifications

    private var notificationsPane: some View {
        Group {
            SettingsSection(title: "Alerts") {
                SettingRow(title: "Warn when running low",
                           subtitle: "Notify once a window drops below the threshold.") {
                    Toggle("", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { on in
                            settings.notificationsEnabled = on
                            if on { model.requestNotificationPermission() }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Warn when running low")
                }
                Divider()
                SettingRow(title: "Threshold") {
                    Picker("", selection: Binding(
                        get: { settings.warnThreshold },
                        set: { settings.warnThreshold = $0 }
                    )) {
                        ForEach(AppSettings.thresholdChoices, id: \.self) { value in
                            Text("\(value)% remaining").tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .disabled(!settings.notificationsEnabled)
                    .accessibilityLabel("Warning threshold")
                }
            }

            Text("Warned once per window per reset cycle.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Appearance

    private var appearancePane: some View {
        Group {
            SettingsSection(title: "Theme") {
                SettingRow(title: "Appearance",
                           subtitle: "Applies to the dashboard, settings, and your placed widgets.") {
                    Picker("", selection: Binding(
                        get: { settings.appearance },
                        set: { settings.appearance = $0; Appearance.apply($0) }
                    )) {
                        ForEach(AppSettings.Appearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .accessibilityLabel("Appearance")
                }
            }

            Text("Auto follows System Settings › Appearance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Advanced

    private var advancedPane: some View {
        Group {
            SettingsSection(title: "Data", emphasized: true) {
                SettingRow(title: "Shared snapshot",
                           subtitle: UsageStore.cacheURLForDisplay) {
                    Button("Reveal") { UsageStore.revealCacheInFinder() }
                }
                Divider()
                SettingRow(title: "Reload widgets",
                           subtitle: "Force every placed widget to re-read the snapshot.") {
                    Button("Reload") {
                        WidgetCenter.shared.reloadAllTimelines()
                        actionConfirmation = "Widgets reloaded."
                    }
                }
                Divider()
                SettingRow(title: "Clear cache",
                           subtitle: "Delete the snapshot and fetch again from scratch.") {
                    Button("Clear…", role: .destructive) {
                        showClearCacheConfirmation = true
                    }
                }
                if let actionConfirmation {
                    Divider()
                    Label(actionConfirmation, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.vertical, LayoutSpacing.compact)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
    }

    private func clearCache() {
        actionConfirmation = "Cache cleared. Fetching fresh usage…"
        UsageStore.clearCache()
        Task {
            await model.refresh()
            actionConfirmation = "Cache cleared and usage refreshed."
        }
    }
}

// MARK: - Login item

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[VibeWidget] login item toggle failed: %@", String(describing: error))
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    var buildVersion: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
