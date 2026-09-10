import Foundation
import AppKit

/// Fetches both providers and keeps the last good result on disk, so a widget
/// waking up to a dead network still has something to draw.
enum UsageStore {

    /// macOS only loads a widget extension that is sandboxed, and a sandboxed
    /// extension cannot see ~/Library/Application Support. The App Group is the
    /// one directory both processes can reach: the unsandboxed app writes it,
    /// the sandboxed widget reads it.
    ///
    /// Read back from Info.plist rather than written here, because macOS makes
    /// the group carry the Team ID of whoever signed the build — and that
    /// differs per machine, since this app is built from source with the
    /// user's own certificate. `generate_project.py` puts one value into the
    /// entitlement and both Info.plists, so what the code opens always matches
    /// what the signature permits.
    static let appGroupIdentifier: String = {
        let key = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier")
        if let identifier = key as? String,
           !identifier.isEmpty, !identifier.hasPrefix("$(") {
            return identifier
        }
        // Unreachable from a build made by generate_project.py. If it ever is,
        // containerURL(for:) returns nil below and the app falls back to its
        // own Application Support — running, but invisible to the widget.
        return "group.com.phonpreecha.vibewidget"
    }()

    private static var containerDirectory: URL {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return group.appendingPathComponent("Library/Application Support/VibeWidget")
        }
        // Only reached if the group entitlement is missing — the app can still
        // run standalone, the widget just will not see anything.
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VibeWidget")
    }

    private static var cacheURL: URL {
        containerDirectory.appendingPathComponent("snapshot.json")
    }

    private static let coder: (JSONEncoder, JSONDecoder) = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }()

    // MARK: - Disk

    static func loadCached() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? coder.1.decode(UsageSnapshot.self, from: data)
    }

    /// Abbreviated for the Advanced pane — the full group container path is
    /// long enough to wrap three times.
    static var cacheURLForDisplay: String {
        cacheURL.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"
        )
    }

    static func revealCacheInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([cacheURL])
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private static func persist(_ snapshot: UsageSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: containerDirectory, withIntermediateDirectories: true
            )
            try coder.0.encode(snapshot).write(to: cacheURL, options: .atomic)
        } catch {
            // A failed cache write is not worth failing the refresh over — the
            // caller already has the fresh snapshot in hand — but it does mean
            // the widget will read stale data, so it is worth a log line.
            NSLog("[VibeWidget] cache write failed at %@: %@",
                  cacheURL.path, String(describing: error))
        }
    }

    // MARK: - Refresh

    /// Codex is a local file read and Claude is a network round trip, so the
    /// two run concurrently and the whole refresh costs about one request.
    static func refresh() async -> UsageSnapshot {
        async let claude = ClaudeUsageProvider.fetch()
        let codex = CodexUsageProvider.fetch()

        var snapshot = UsageSnapshot(
            claude: await claude,
            codex: codex,
            capturedAt: Date()
        )

        // Carry forward the last known numbers for whichever provider failed,
        // rather than showing an empty card. The error stays attached so the
        // UI can mark the values as stale.
        if let cached = loadCached() {
            snapshot.claude = merge(fresh: snapshot.claude, cached: cached.claude)
            snapshot.codex = merge(fresh: snapshot.codex, cached: cached.codex)
        }

        persist(snapshot)
        return snapshot
    }

    private static func merge(fresh: ProviderUsage, cached: ProviderUsage) -> ProviderUsage {
        guard fresh.error != nil else { return fresh }
        var merged = fresh
        merged.session = merged.session ?? cached.session
        merged.weekly = merged.weekly ?? cached.weekly
        merged.plan = merged.plan ?? cached.plan
        return merged
    }
}
