import AppKit
import Foundation

/// Notices when a newer release exists and, on request, hands the upgrade to
/// Homebrew.
///
/// Deliberately not Sparkle. Sparkle swaps the bundle itself, which would leave
/// Homebrew managing a version that is no longer on disk — and this app is
/// installed by Homebrew. Fetching, verifying and staging a release is work
/// Homebrew already does; the only thing missing was anyone noticing that a
/// release had happened.
@MainActor
final class UpdateChecker: ObservableObject {

    /// Shared because the check belongs to the app rather than to any window,
    /// and the panel it reports into is rebuilt constantly.
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case available(String)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private static let latestRelease = URL(
        string: "https://api.github.com/repos/ballunstar/vibe-widget/releases/latest")!

    /// Four times a day. Unauthenticated GitHub allows sixty calls an hour per
    /// address, and nothing here is urgent enough to spend more of that.
    private static let interval: TimeInterval = 6 * 60 * 60

    private var timer: Timer?

    private init() {}

    // MARK: - What this install is

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static func tool(_ name: String) -> URL? {
        ["/opt/homebrew/bin/", "/usr/local/bin/"]
            .map { URL(fileURLWithPath: $0 + name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Both commands present is what makes this a Homebrew install. Without
    /// them an update offer would be one this app cannot honour, so it stays
    /// quiet instead.
    static var isHomebrewInstall: Bool {
        tool("brew") != nil && tool("vibewidget-refresh") != nil
    }

    // MARK: - Checking

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil

        guard enabled, Self.isHomebrewInstall else {
            state = .idle
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
        Task { await check() }
    }

    private struct Release: Decodable {
        let tag_name: String
    }

    func check() async {
        guard Self.isHomebrewInstall, state != .installing else { return }

        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // A failed check says nothing worth interrupting anyone over: the app
        // reports usage either way, and the next one is a few hours out.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return }

        var tag = release.tag_name
        if tag.hasPrefix("v") { tag.removeFirst() }

        state = tag.compare(Self.currentVersion, options: .numeric) == .orderedDescending
            ? .available(tag)
            : .idle
    }

    // MARK: - Installing

    func install() {
        guard Self.isHomebrewInstall,
              let brew = Self.tool("brew"),
              let refresh = Self.tool("vibewidget-refresh") else { return }

        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VibeWidget")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logFile = logs.appendingPathComponent("update.log").path

        // `brew update` first, or Homebrew answers out of a tap it last read
        // days ago and reports this version as the newest there is.
        //
        // vibewidget-refresh stops this app before overwriting the bundle, so
        // the work has to outlive the process that started it — a child of a
        // terminated process is reparented rather than killed, but its output
        // has nowhere left to go, hence the log.
        let script = "'\(brew.path)' update"
            + " && '\(brew.path)' upgrade vibewidget"
            + " && '\(refresh.path)'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "{ \(script) ; } >> '\(logFile)' 2>&1"]
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in
                // A success ends with this app replaced and restarted, so only
                // the failure is ever seen here.
                guard status != 0 else { return }
                self?.state = .failed("Homebrew could not finish — see Console at ~/Library/Logs/VibeWidget/update.log")
            }
        }

        do {
            try process.run()
            state = .installing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
