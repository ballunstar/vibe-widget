import Foundation

/// Codex writes a `rate_limits` snapshot into its session rollout logs after
/// every turn, so its official numbers are already on disk — no token, no
/// network call. We just find the freshest one.
enum CodexUsageProvider {

    private static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    /// How many of the most recent rollout files to look through before giving
    /// up. The newest file usually wins on the first try; the extras cover the
    /// case where the last session ended before any limits came back.
    private static let filesToScan = 8

    /// Only read the tail of each log. These grow to megabytes and the snapshot
    /// we want is always near the end.
    private static let tailByteCount = 512 * 1024

    enum ProviderError: LocalizedError {
        case noSessions
        case noRateLimitData

        var errorDescription: String? {
            switch self {
            case .noSessions: return "No Codex CLI sessions found"
            case .noRateLimitData: return "Run the Codex CLI once to populate usage"
            }
        }
    }

    // MARK: - Rollout decoding

    private struct RolloutLine: Decodable {
        struct Payload: Decodable { let rate_limits: RateLimits? }
        struct RateLimits: Decodable {
            struct Window: Decodable {
                let used_percent: Double?
                let resets_at: Double?
            }
            let limit_id: String?
            let primary: Window?
            let secondary: Window?
            let plan_type: String?
        }
        let timestamp: String?
        let payload: Payload?
    }

    private static func window(from w: RateLimits.Window?) -> UsageWindow? {
        guard let w, let used = w.used_percent else { return nil }
        let resetsAt = w.resets_at.map { Date(timeIntervalSince1970: $0) }

        // The log records what was true when Codex last ran. If that window has
        // since rolled over, the allowance is back to full — reporting the old
        // percentage would be actively misleading.
        if let resetsAt, resetsAt < Date() {
            return UsageWindow(usedPercent: 0, resetsAt: nil)
        }
        return UsageWindow(usedPercent: used, resetsAt: resetsAt)
    }

    private typealias RateLimits = RolloutLine.RateLimits

    // MARK: - File access

    private static func recentRolloutFiles() -> [URL] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [(URL, Date)] = []
        for case let url as URL in walker where url.lastPathComponent.hasSuffix(".jsonl") {
            guard url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            found.append((url, modified))
        }
        return found.sorted { $0.1 > $1.1 }.prefix(filesToScan).map(\.0)
    }

    private static func tailLines(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(tailByteCount) ? size - UInt64(tailByteCount) : 0
        try? handle.seek(toOffset: offset)

        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }

        var lines = text.components(separatedBy: "\n")
        // A mid-line seek leaves a partial first line that will not parse.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    // MARK: - Fetch

    static func fetch() -> ProviderUsage {
        var result = ProviderUsage(provider: .codex)

        let files = recentRolloutFiles()
        guard !files.isEmpty else {
            result.error = ProviderError.noSessions.errorDescription
            return result
        }

        let decoder = JSONDecoder()
        for file in files {
            for line in tailLines(of: file).reversed() {
                guard line.contains("\"rate_limits\""),
                      let data = line.data(using: .utf8),
                      let parsed = try? decoder.decode(RolloutLine.self, from: data),
                      let limits = parsed.payload?.rate_limits
                else { continue }

                // Codex emits several limit groups; "codex" is the plan-level
                // one. The others ("premium") carry null windows for most plans.
                guard limits.limit_id == "codex",
                      limits.primary != nil || limits.secondary != nil
                else { continue }

                result.session = window(from: limits.primary)
                result.weekly = window(from: limits.secondary)
                result.plan = limits.plan_type
                return result
            }
        }

        result.error = ProviderError.noRateLimitData.errorDescription
        return result
    }
}
