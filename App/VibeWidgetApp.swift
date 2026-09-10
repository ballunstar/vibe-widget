import SwiftUI
import WidgetKit
import UserNotifications

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private let settings = AppSettings.shared

    init() {
        snapshot = UsageStore.loadCached() ?? .empty
        rescheduleTimer()
        if settings.notificationsEnabled { requestNotificationPermission() }
        Task { await refresh() }
    }

    deinit { timer?.invalidate() }

    // MARK: - Refresh

    /// Rebuilds the timer from current preferences. Called whenever the
    /// interval or the automatic-refresh switch changes.
    func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.automaticRefresh else { return }

        let interval = TimeInterval(max(1, settings.refreshIntervalMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshot = await UsageStore.refresh()
        isRefreshing = false

        notifyIfLow()
        // The widget reads the same cache the refresh just wrote.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Menu bar title

    /// Smallest remaining slice across everything.
    private var lowest: (provider: ProviderUsage.Provider, window: UsageWindow)? {
        snapshot.providers
            .flatMap { usage in
                [usage.session, usage.weekly].compactMap { $0 }.map { (usage.provider, $0) }
            }
            .min { $0.1.remainingPercent < $1.1.remainingPercent }
    }

    private func lowestFor(_ provider: ProviderUsage.Provider) -> UsageWindow? {
        let usage = provider == .claude ? snapshot.claude : snapshot.codex
        return [usage.session, usage.weekly].compactMap { $0 }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    /// Takes the mode as an argument rather than reading it from settings: the
    /// App struct re-renders on @AppStorage changes, but not on this object's
    /// settings, so reading it here would leave the title stale until the next
    /// refresh.
    func menuBarTitle(for display: AppSettings.MenuBarDisplay) -> String {
        guard snapshot.hasData else { return "—" }
        switch display {
        case .iconOnly:
            return ""
        case .lowestRemaining:
            guard let lowest else { return "—" }
            return "\(Int(lowest.window.remainingPercent.rounded()))%"
        case .claudeOnly:
            guard let w = lowestFor(.claude) else { return "—" }
            return "\(Int(w.remainingPercent.rounded()))%"
        case .codexOnly:
            guard let w = lowestFor(.codex) else { return "—" }
            return "\(Int(w.remainingPercent.rounded()))%"
        }
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    NSLog("[VibeWidget] notification permission: %@", String(describing: error))
                } else if !granted {
                    NSLog("[VibeWidget] notification permission denied")
                }
            }
    }

    /// Warns once per window per reset cycle. Keying on the reset timestamp is
    /// what stops a 15-minute refresh loop from firing the same alert all day:
    /// the key only changes when the window actually rolls over.
    private func notifyIfLow() {
        guard settings.notificationsEnabled else { return }
        let threshold = Double(settings.warnThreshold)
        let defaults = UserDefaults(suiteName: UsageStore.appGroupIdentifier) ?? .standard

        for usage in snapshot.providers {
            for (label, window) in [("session", usage.session), ("weekly", usage.weekly)] {
                guard let window, window.remainingPercent < threshold else { continue }

                // One key per window, holding the cycle it last warned for.
                // Keying the cycle into the *name* instead would leave a new
                // dead key in defaults after every reset, forever.
                let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
                let key = "warned.\(usage.provider.rawValue).\(label)"
                guard defaults.string(forKey: key) != cycle else { continue }
                defaults.set(cycle, forKey: key)

                let content = UNMutableNotificationContent()
                content.title = "\(usage.provider.displayName) running low"
                content.body = "\(Int(window.remainingPercent.rounded()))% of your "
                    + "\(label == "session" ? "5-hour" : "weekly") allowance left."
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "\(key).\(cycle)",
                                          content: content, trigger: nil)
                ) { error in
                    if let error {
                        NSLog("[VibeWidget] notification failed: %@", String(describing: error))
                    } else {
                        NSLog("[VibeWidget] warned %@ %@ (%d%% left)",
                              usage.provider.rawValue, label,
                              Int(window.remainingPercent.rounded()))
                    }
                }
            }
        }
    }
}

/// The menu itself lives in a View, not in the App struct, because
/// `openWindow` is a *view* environment value — reading it from `App` yields a
/// non-functional action.
struct MenuBarMenu: View {
    @ObservedObject var model: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Dashboard") { open(VibeWidgetApp.dashboardWindowID) }
            .keyboardShortcut("d")
        Button("Settings…") { open(VibeWidgetApp.settingsWindowID) }
            .keyboardShortcut(",")

        Divider()

        Button(model.isRefreshing ? "Refreshing…" : "Refresh Now") {
            Task { await model.refresh() }
        }
        .disabled(model.isRefreshing)

        Divider()

        Button("Quit VibeWidget") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// A menu bar app is not frontmost when its menu is clicked, so the window
    /// would otherwise open behind whatever the user was looking at.
    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Applies the stored appearance at launch. AppKit needs this set on
/// NSApplication — a SwiftUI `.preferredColorScheme` on the scenes does not
/// reach window chrome such as the title bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply(AppSettings.shared.appearance)
    }
}

enum Appearance {
    static func apply(_ appearance: AppSettings.Appearance) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Placed widgets render in their own process, so they need telling.
        WidgetCenter.shared.reloadAllTimelines()
    }
}

@main
struct VibeWidgetApp: App {
    static let dashboardWindowID = "dashboard"
    static let settingsWindowID = "settings"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = UsageViewModel()

    /// Deliberately @AppStorage rather than the AppSettings object. An
    /// `@ObservedObject` here re-subscribes every time SwiftUI rebuilds the App
    /// value, which re-invalidates the scene graph and spins the launch in an
    /// endless makeMainMenu loop — the app never finishes launching and no
    /// status item is ever created.
    @AppStorage("showInMenuBar", store: UserDefaults(suiteName: UsageStore.appGroupIdentifier))
    private var showInMenuBar = true

    @AppStorage("menuBarDisplay", store: UserDefaults(suiteName: UsageStore.appGroupIdentifier))
    private var menuBarDisplayRaw = AppSettings.MenuBarDisplay.iconOnly.rawValue

    private var menuBarTitle: String {
        let display = AppSettings.MenuBarDisplay(rawValue: menuBarDisplayRaw) ?? .lowestRemaining
        return model.menuBarTitle(for: display)
    }

    /// The status item mark.
    ///
    /// Marked as a template image, which is what lets one black-on-transparent
    /// asset serve both menu bar appearances: macOS re-colours templates to
    /// suit the bar it is drawing into, so no light/dark pair is needed.
    private var menuBarIcon: Image {
        guard let image = NSImage(named: "navicon") else {
            return Image(systemName: "gauge.with.needle")
        }
        image.isTemplate = true
        image.size = NSSize(width: 15, height: 15)
        return Image(nsImage: image)
    }

    var body: some Scene {
        // Clicking the menu bar item opens a menu; the numbers live in the
        // dashboard window rather than in a popover.
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu(model: model)
        } label: {
            menuBarIcon
            if !menuBarTitle.isEmpty {
                Text(menuBarTitle)
            }
        }

        Window("VibeWidget", id: Self.dashboardWindowID) {
            DashboardView(model: model)
        }
        .windowResizability(.contentMinSize)

        Window("Settings", id: Self.settingsWindowID) {
            SettingsView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
