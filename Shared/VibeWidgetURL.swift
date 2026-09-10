import Foundation

/// The URL a widget opens when clicked.
///
/// Shared so the widget that emits it and the app that handles it cannot drift.
/// The scheme is declared in the app's Info.plist under CFBundleURLTypes —
/// without that, macOS has nothing to route this to.
enum VibeWidgetURL {
    static let scheme = "vibewidget"
    static let dashboardHost = "dashboard"

    static let dashboard = URL(string: "\(scheme)://\(dashboardHost)")!

    static func isDashboard(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == dashboardHost
    }
}
