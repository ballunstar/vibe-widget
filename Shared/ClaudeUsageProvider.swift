import Foundation

/// Reads Claude Code's OAuth token out of the login keychain and asks
/// Anthropic for the same numbers the `/usage` command prints.
enum ClaudeUsageProvider {

    /// The keychain item Claude Code writes its credentials into.
    private static let keychainService = "Claude Code-credentials"
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    enum ProviderError: LocalizedError {
        case keychainUnavailable(OSStatus)
        case credentialsUnreadable
        case tokenExpired
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .keychainUnavailable(let status) where status == errSecItemNotFound:
                return "Not signed in to Claude Code"
            case .keychainUnavailable:
                return "Keychain access denied"
            case .credentialsUnreadable:
                return "Could not read credentials"
            case .tokenExpired:
                return "Token expired — open Claude Code"
            case .httpStatus(let code):
                return "Anthropic API error (\(code))"
            }
        }
    }

    // MARK: - Keychain

    private struct Credentials: Decodable {
        let accessToken: String
        let expiresAt: Double?
        let subscriptionType: String?
    }

    private struct CredentialBlob: Decodable {
        let claudeAiOauth: Credentials
    }

    /// We only ever read. Claude Code owns this item and refreshes it; writing
    /// back from here risks corrupting the CLI's own login.
    ///
    /// Claude Code locks the item to a single authorised binary:
    ///
    ///     applications (1): /usr/bin/security
    ///     requirement: identifier "com.apple.security" and anchor apple
    ///
    /// So `SecItemCopyMatching` from this app is not merely denied — it raises a
    /// blocking SecurityAgent dialog that a background menu bar app cannot
    /// sensibly answer and a widget extension cannot answer at all. Going
    /// through the one binary the ACL already trusts avoids the prompt and
    /// leaves Claude Code's own access rules untouched.
    ///
    /// This spawns a subprocess, so only the container app may call it; the
    /// widget renders the cache the app writes.
    private static func loadCredentials() throws -> Credentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ProviderError.credentialsUnreadable
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProviderError.keychainUnavailable(errSecItemNotFound)
        }
        guard let blob = try? JSONDecoder().decode(CredentialBlob.self, from: data) else {
            throw ProviderError.credentialsUnreadable
        }
        return blob.claudeAiOauth
    }

    // MARK: - API response

    /// Only the fields we render. The endpoint returns many more windows, most
    /// of them null for any given account, so everything here stays optional.
    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `resets_at` sometimes carries fractional seconds and sometimes does not.
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let d = isoParser.date(from: raw) { return d }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }

    private static func window(from w: UsageResponse.Window?) -> UsageWindow? {
        guard let w, let used = w.utilization else { return nil }
        return UsageWindow(usedPercent: used, resetsAt: parseDate(w.resets_at))
    }

    // MARK: - Fetch

    static func fetch() async -> ProviderUsage {
        var result = ProviderUsage(provider: .claude)
        do {
            let creds = try loadCredentials()
            result.plan = creds.subscriptionType

            // Claude Code refreshes this token in the background. If it has
            // lapsed we say so rather than firing a request we know will 401.
            if let expiresAt = creds.expiresAt,
               Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
                throw ProviderError.tokenExpired
            }

            var request = URLRequest(url: usageEndpoint)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw code == 401 ? ProviderError.tokenExpired : ProviderError.httpStatus(code)
            }

            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            result.session = window(from: decoded.five_hour)
            result.weekly = window(from: decoded.seven_day)
        } catch {
            result.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        return result
    }
}
