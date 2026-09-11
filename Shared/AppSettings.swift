import Foundation
import Combine
import SwiftUI

/// User preferences. Stored in the App Group suite rather than the app's own
/// defaults so the widget can honour the display options too.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: UsageStore.appGroupIdentifier) ?? .standard

        // Before register(defaults:), which would answer this lookup with the
        // fallback and make an upgrade look like a fresh install — quietly
        // resetting an interval the user had chosen.
        if defaults.object(forKey: Key.refreshIntervalSeconds) == nil,
           let legacyMinutes = defaults.object(forKey: Key.refreshIntervalMinutes) as? Int,
           legacyMinutes > 0 {
            defaults.set(legacyMinutes * 60, forKey: Key.refreshIntervalSeconds)
        }

        defaults.register(defaults: [
            Key.automaticRefresh: true,
            Key.refreshIntervalSeconds: 900,
            Key.showInMenuBar: true,
            Key.menuBarDisplay: MenuBarDisplay.iconOnly.rawValue,
            Key.compactNumbers: false,
            Key.showResetTime: true,
            Key.showWeekly: true,
            Key.notificationsEnabled: false,
            Key.warnThreshold: 20,
            Key.appearance: Appearance.system.rawValue,
        ])
    }

    private enum Key {
        static let automaticRefresh = "automaticRefresh"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"   // legacy, migrated
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let showInMenuBar = "showInMenuBar"
        static let menuBarDisplay = "menuBarDisplay"
        static let compactNumbers = "compactNumbers"
        static let showResetTime = "showResetTime"
        static let showWeekly = "showWeekly"
        static let notificationsEnabled = "notificationsEnabled"
        static let warnThreshold = "warnThreshold"
        static let appearance = "appearance"
    }

    /// What the menu bar title shows when it is not just an icon.
    enum MenuBarDisplay: String, CaseIterable, Identifiable {
        case lowestRemaining, claudeOnly, codexOnly, iconOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lowestRemaining: return "Lowest remaining"
            case .claudeOnly: return "Claude only"
            case .codexOnly: return "ChatGPT only"
            case .iconOnly: return "Icon only"
            }
        }
    }

    /// Light, dark, or whatever the OS is doing.
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Auto (match system)"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        /// nil means "inherit", which is what both AppKit and SwiftUI want in
        /// order to keep following the system.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system }
        set { set(newValue.rawValue, Key.appearance) }
    }

    /// Options offered for the refresh timer, in seconds.
    static let refreshChoices = [30, 60, 300, 600, 900, 1800, 3600]

    static func refreshLabel(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "Every \(seconds) seconds"
        case 60: return "Every minute"
        case 3600: return "Every hour"
        default: return "Every \(seconds / 60) minutes"
        }
    }

    // MARK: - Values

    var automaticRefresh: Bool {
        get { defaults.bool(forKey: Key.automaticRefresh) }
        set { set(newValue, Key.automaticRefresh) }
    }

    /// Seconds, not minutes: the shortest useful interval is now below a
    /// minute, which whole minutes cannot express.
    var refreshIntervalSeconds: Int {
        get { defaults.integer(forKey: Key.refreshIntervalSeconds) }
        set { set(newValue, Key.refreshIntervalSeconds) }
    }

    var showInMenuBar: Bool {
        get { defaults.bool(forKey: Key.showInMenuBar) }
        set { set(newValue, Key.showInMenuBar) }
    }

    var menuBarDisplay: MenuBarDisplay {
        get {
            MenuBarDisplay(rawValue: defaults.string(forKey: Key.menuBarDisplay) ?? "")
                ?? .lowestRemaining
        }
        set { set(newValue.rawValue, Key.menuBarDisplay) }
    }

    var compactNumbers: Bool {
        get { defaults.bool(forKey: Key.compactNumbers) }
        set { set(newValue, Key.compactNumbers) }
    }

    var showResetTime: Bool {
        get { defaults.bool(forKey: Key.showResetTime) }
        set { set(newValue, Key.showResetTime) }
    }

    /// When off, only the 5-hour window is shown and it takes the full column.
    var showWeekly: Bool {
        get { defaults.bool(forKey: Key.showWeekly) }
        set { set(newValue, Key.showWeekly) }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { set(newValue, Key.notificationsEnabled) }
    }

    /// Warn once a window drops to this many percent remaining.
    var warnThreshold: Int {
        get { defaults.integer(forKey: Key.warnThreshold) }
        set { set(newValue, Key.warnThreshold) }
    }

    static let thresholdChoices = [10, 20, 30, 50]

    private func set(_ value: Any, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }

    /// Read-only accessor for the widget, which has no reason to build the
    /// whole observable object just to read two display flags.
    struct WidgetPreferences {
        let compactNumbers: Bool
        let showResetTime: Bool
        let showWeekly: Bool
        let appearance: Appearance

        static var current: WidgetPreferences {
            let d = UserDefaults(suiteName: UsageStore.appGroupIdentifier)
            return WidgetPreferences(
                compactNumbers: d?.bool(forKey: Key.compactNumbers) ?? false,
                // Absent means "never written", and the shipped default is on.
                showResetTime: d?.object(forKey: Key.showResetTime) as? Bool ?? true,
                showWeekly: d?.object(forKey: Key.showWeekly) as? Bool ?? true,
                appearance: Appearance(rawValue: d?.string(forKey: Key.appearance) ?? "") ?? .system
            )
        }
    }
}
