import AppIntents
import WidgetKit

/// Which service a single-provider widget shows. Backed by the same `Provider`
/// case the rest of the app uses; the raw values are what get written into the
/// widget's stored configuration, so they must stay stable.
enum ProviderChoice: String, AppEnum {
    case claude
    case chatgpt

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Service" }

    static var caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] {
        [.claude: "Claude", .chatgpt: "ChatGPT"]
    }

    var provider: ProviderUsage.Provider {
        switch self {
        case .claude: return .claude
        case .chatgpt: return .codex
        }
    }
}

/// Whether one widget shows the weekly window.
///
/// Three states rather than a switch: an app-wide preference already exists, so
/// a plain on/off here would silently disagree with it. "Follow Settings" keeps
/// that preference authoritative unless this widget is told otherwise.
enum WeeklyVisibility: String, AppEnum {
    case followSettings
    case show
    case hide

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Weekly Usage" }

    static var caseDisplayRepresentations: [WeeklyVisibility: DisplayRepresentation] {
        [.followSettings: "Follow Settings", .show: "Show", .hide: "Hide"]
    }

    /// nil means "no opinion" — the app-wide setting decides.
    var override: Bool? {
        switch self {
        case .followSettings: return nil
        case .show: return true
        case .hide: return false
        }
    }
}

/// The widget's edit sheet.
struct SelectProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Widget Options" }
    static var description: IntentDescription {
        IntentDescription("Pick the service this widget tracks and what it shows.")
    }

    @Parameter(title: "Service", default: .claude)
    var provider: ProviderChoice

    @Parameter(title: "Weekly usage", default: .followSettings)
    var weekly: WeeklyVisibility
}

