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

        let interval = TimeInterval(max(15, settings.refreshIntervalSeconds))
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
    /// The menu bar reports the **session** window only.
    ///
    /// Not the tightest of the two: the weekly figure moves slowly and, for
    /// ChatGPT, is only as fresh as the last Codex CLI run — so a menu bar
    /// driven by it can sit at a stale number for hours while the 5-hour
    /// window it is meant to reflect is long since full. The widgets still
    /// show both.
    private var lowest: (provider: ProviderUsage.Provider, window: UsageWindow)? {
        snapshot.providers
            .compactMap { usage in usage.session.map { (usage.provider, $0) } }
            .min { $0.1.remainingPercent < $1.1.remainingPercent }
    }

    /// Percent remaining in one provider's session (5-hour) window, which is
    /// what the menu bar gauge draws. Nil until there is a reading.
    func remaining(for provider: ProviderUsage.Provider) -> Double? {
        guard snapshot.hasData else { return nil }
        return lowestFor(provider)?.remainingPercent
    }

    private func lowestFor(_ provider: ProviderUsage.Provider) -> UsageWindow? {
        (provider == .claude ? snapshot.claude : snapshot.codex).session
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

/// Applies the stored appearance at launch. AppKit needs this set on
/// NSApplication — a SwiftUI `.preferredColorScheme` on the scenes does not
/// reach window chrome such as the title bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply(AppSettings.shared.appearance)
        UpdateChecker.shared.setEnabled(AppSettings.shared.checkForUpdates)
        AppAccess.apply(menuBarVisible: AppSettings.shared.showInMenuBar)
    }

    /// Clicking a widget sends `vibewidget://dashboard` here. A menu bar app is
    /// not frontmost at that point, so it has to raise itself as well.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: VibeWidgetURL.isDashboard) else { return }
        NSApp.activate(ignoringOtherApps: true)
        DashboardOpenRequest.shared.open()
    }

    /// When the menu-bar item is hidden the app becomes a regular Dock app.
    /// Reopening it should restore the dashboard instead of activating an
    /// apparently empty process.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        if let dashboard = sender.windows.first(where: { $0.title == "VibeWidget" }) {
            dashboard.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return false
        }
        DashboardOpenRequest.shared.open()
        return true
    }
}

/// Bridges the delegate's URL callback to SwiftUI, which is the only side that
/// can open a `Window` scene.
///
/// A counter rather than a flag: the label that services these requests is
/// mounted only while the menu bar item is visible, so a request can be raised
/// with nobody listening. A flag left standing at `true` would then swallow
/// every later request, because setting `true` again is not a change.
@MainActor
final class DashboardOpenRequest: ObservableObject {
    static let shared = DashboardOpenRequest()
    @Published private(set) var requestID = 0
    func open() { requestID += 1 }
}

/// The status item's label, and the app's only permanently-mounted view.
///
/// The menu's contents exist solely while the menu is open, so this is where a
/// widget click has to be picked up — `openWindow` is a view environment value
/// and needs somewhere alive to be read from.
struct MenuBarLabel: View {
    let icon: Image
    let title: String
    let accessibilityTitle: String
    @ObservedObject private var request = DashboardOpenRequest.shared
    @Environment(\.openWindow) private var openWindow
    @State private var servicedID = 0

    var body: some View {
        HStack(spacing: 2) {
            icon.accessibilityHidden(true)
            if !title.isEmpty {
                Text(title)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .background {
            Color.clear
                .frame(width: 0, height: 0)
                // `onAppear` as well as `onChange`: turning the menu bar item
                // back on remounts this view, and a request raised while it was
                // gone still deserves its window.
                .onAppear { serviceRequest() }
                .onChange(of: request.requestID) { _, _ in serviceRequest() }
        }
    }

    private func serviceRequest() {
        guard request.requestID != servicedID else { return }
        servicedID = request.requestID
        openWindow(id: VibeWidgetApp.dashboardWindowID)
        NSApp.activate(ignoringOtherApps: true)
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

/// A hidden menu-bar item must not make a background-only app unreachable.
/// The preference therefore switches the app's access surface: menu bar while
/// visible, Dock while hidden.
enum AppAccess {
    static func apply(menuBarVisible: Bool) {
        NSApp.setActivationPolicy(menuBarVisible ? .accessory : .regular)
        if !menuBarVisible { NSApp.activate(ignoringOtherApps: true) }
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
    /// The status item mark: a split donut, Claude's half on the left and
    /// ChatGPT's on the right, each filled to what is left.
    ///
    /// Redrawn whenever the model publishes, which is what makes it track usage
    /// — the App re-evaluates this label on every refresh.
    private var menuBarIcon: Image {
        Image(nsImage: MenuBarGauge.image(claude: model.remaining(for: .claude),
                                          chatgpt: model.remaining(for: .codex)))
    }

    private var menuBarAccessibilityTitle: String {
        let claude = model.remaining(for: .claude)
            .map { "\(Int($0.rounded())) percent" } ?? "no data"
        let chatgpt = model.remaining(for: .codex)
            .map { "\(Int($0.rounded())) percent" } ?? "no data"
        return "VibeWidget. Claude \(claude) remaining. ChatGPT \(chatgpt) remaining."
    }

    var body: some Scene {
        // Clicking the menu bar item opens a menu; the numbers live in the
        // dashboard window rather than in a popover.
        // .window rather than .menu: a standard menu cannot draw the logos and
        // progress bars this panel is built from.
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(icon: menuBarIcon, title: menuBarTitle,
                         accessibilityTitle: menuBarAccessibilityTitle)
        }
        .menuBarExtraStyle(.window)

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
