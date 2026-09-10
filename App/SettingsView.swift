import SwiftUI
import ServiceManagement
import WidgetKit

// MARK: - Layout helpers

/// A titled group of rows, matching the boxed sections in the design.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider().padding(.horizontal, 16)
            content
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

/// One row: label, optional explanation, and a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: UsageViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var section: Pane = .general

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
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 840, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 20))
                    .foregroundStyle(ProviderUsage.Provider.claude.accent)
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 0) {
                    Text("VibeWidget").font(.system(size: 15, weight: .bold))
                    Text("Settings").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 14)

            ForEach(Pane.allCases) { pane in
                Button {
                    section = pane
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: pane.icon)
                            .frame(width: 18)
                            .foregroundStyle(section == pane
                                             ? ProviderUsage.Provider.claude.accent
                                             : Color.secondary)
                        Text(pane.label).font(.system(size: 12.5, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(section == pane ? Color.primary.opacity(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 210)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(section == .general ? "Settings" : section.label)
                    .font(.system(size: 26, weight: .bold))
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch section {
                    case .general: generalPane
                    case .accounts: accountsPane
                    case .notifications: notificationsPane
                    case .appearance: appearancePane
                    case .advanced: advancedPane
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }

            Divider()
            HStack {
                Text("VibeWidget \(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
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
                }
                Divider().padding(.horizontal, 16)
                SettingRow(title: "Refresh interval") {
                    Picker("", selection: Binding(
                        get: { settings.refreshIntervalMinutes },
                        set: { settings.refreshIntervalMinutes = $0; model.rescheduleTimer() }
                    )) {
                        ForEach(AppSettings.refreshChoices, id: \.self) { minutes in
                            Text(AppSettings.refreshLabel(minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .disabled(!settings.automaticRefresh)
                }
            }

            SettingsSection(title: "Menu Bar") {
                SettingRow(title: "Show VibeWidget in menu bar",
                           subtitle: "Display quick usage info in the menu bar.") {
                    Toggle("", isOn: Binding(
                        get: { settings.showInMenuBar },
                        set: { settings.showInMenuBar = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider().padding(.horizontal, 16)
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
                }
            }

            SettingsSection(title: "Widgets") {
                SettingRow(title: "Use compact numbers",
                           subtitle: "Show smaller, cleaner numbers in widgets.") {
                    Toggle("", isOn: Binding(
                        get: { settings.compactNumbers },
                        set: { settings.compactNumbers = $0; WidgetCenter.shared.reloadAllTimelines() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider().padding(.horizontal, 16)
                SettingRow(title: "Show reset time",
                           subtitle: "Display when each window resets.") {
                    Toggle("", isOn: Binding(
                        get: { settings.showResetTime },
                        set: { settings.showResetTime = $0; WidgetCenter.shared.reloadAllTimelines() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
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
                    Divider().padding(.horizontal, 16)
                    SettingRow(title: "Status") { StatusBadge(usage: usage) }
                    Divider().padding(.horizontal, 16)
                    SettingRow(title: "Source", subtitle: sourceDescription(usage.provider)) {
                        EmptyView()
                    }
                }
            }

            Text("Sign in and out from the Claude Code and Codex CLIs — VibeWidget only reads what they store.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func sourceDescription(_ provider: ProviderUsage.Provider) -> String {
        switch provider {
        case .claude:
            return "api.anthropic.com/api/oauth/usage, authorised with the token Claude Code keeps in your keychain — or in ~/.claude/.credentials.json when it cannot use the keychain."
        case .codex:
            return "~/.codex/sessions — the rate_limits snapshot the Codex CLI writes into its own session logs."
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
                }
                Divider().padding(.horizontal, 16)
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
                }
            }

            Text("You are warned once per window per reset cycle, so a long session will not repeat the same alert.")
                .font(.system(size: 10.5))
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
                }
            }

            Text("Auto follows System Settings › Appearance, including the automatic light-to-dark switch through the day.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Advanced

    private var advancedPane: some View {
        Group {
            SettingsSection(title: "Data") {
                SettingRow(title: "Shared snapshot",
                           subtitle: UsageStore.cacheURLForDisplay) {
                    Button("Reveal") { UsageStore.revealCacheInFinder() }
                }
                Divider().padding(.horizontal, 16)
                SettingRow(title: "Reload widgets",
                           subtitle: "Force every placed widget to re-read the snapshot.") {
                    Button("Reload") { WidgetCenter.shared.reloadAllTimelines() }
                }
                Divider().padding(.horizontal, 16)
                SettingRow(title: "Clear cache",
                           subtitle: "Delete the snapshot and fetch again from scratch.") {
                    Button("Clear", role: .destructive) {
                        UsageStore.clearCache()
                        Task { await model.refresh() }
                    }
                }
            }
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
