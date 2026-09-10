import Foundation

/// One rate-limit window (a 5-hour or weekly bucket) for either provider.
struct UsageWindow: Codable, Hashable {
    /// Percent of the allowance already consumed, 0...100.
    var usedPercent: Double
    /// When this window rolls over, if the provider told us.
    var resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// Everything we know about one provider at a moment in time.
struct ProviderUsage: Codable, Hashable {
    var provider: Provider
    /// The short rolling window: 5 hours for both Claude and Codex.
    var session: UsageWindow?
    /// The long rolling window: 7 days for both.
    var weekly: UsageWindow?
    /// Plan name as the provider reports it ("max", "plus", ...). Display only.
    var plan: String?
    /// Set when we could not refresh; the windows above may still hold stale data.
    var error: String?

    enum Provider: String, Codable, CaseIterable {
        // The raw values are persisted in the cached snapshot and in the
        // notification dedupe keys, so `codex` stays as-is even though the
        // product is presented as ChatGPT.
        case claude, codex

        var displayName: String {
            switch self {
            case .claude: return "Claude"
            case .codex: return "ChatGPT"
            }
        }

        /// Bundled logo, present in both the app and the widget target.
        var logoAsset: String {
            switch self {
            case .claude: return "claude"
            case .codex: return "chatgpt"
            }
        }
    }
}

/// The single blob the app writes and the widget reads.
struct UsageSnapshot: Codable, Hashable {
    var claude: ProviderUsage
    var codex: ProviderUsage
    /// When this snapshot was assembled — drives the "updated 3m ago" label.
    var capturedAt: Date

    static var placeholder: UsageSnapshot {
        UsageSnapshot(
            claude: ProviderUsage(
                provider: .claude,
                session: UsageWindow(usedPercent: 12, resetsAt: nil),
                weekly: UsageWindow(usedPercent: 34, resetsAt: nil),
                plan: "max"
            ),
            codex: ProviderUsage(
                provider: .codex,
                session: UsageWindow(usedPercent: 61, resetsAt: nil),
                weekly: UsageWindow(usedPercent: 28, resetsAt: nil),
                plan: "plus"
            ),
            capturedAt: Date()
        )
    }

    /// Nothing cached yet — the container app has never completed a refresh.
    static var empty: UsageSnapshot {
        UsageSnapshot(
            claude: ProviderUsage(provider: .claude),
            codex: ProviderUsage(provider: .codex),
            capturedAt: .distantPast
        )
    }

    /// False until at least one real window has been read from either provider.
    var hasData: Bool {
        providers.contains { $0.session != nil || $0.weekly != nil }
    }

    var providers: [ProviderUsage] { [claude, codex] }
}
