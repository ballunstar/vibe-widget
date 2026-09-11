import Foundation

/// Reads Claude Code's OAuth token out of the login keychain and asks
/// Anthropic for the same numbers the `/usage` command prints.
enum ClaudeUsageProvider {

    /// The keychain item Claude Code writes its credentials into.
    private static let keychainService = "Claude Code-credentials"

    /// Where Claude Code keeps the same JSON when it cannot use the keychain.
    /// Same shape, so either source decodes into `CredentialBlob`.
    private static var credentialsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    enum ProviderError: LocalizedError {
        case notSignedIn
        /// Carries what `security` printed. Anything other than a missing item
        /// is rare enough that its own words beat a guess at what went wrong.
        case keychainRefused(String)
        case credentialsUnreadable
        /// The stored token has lapsed. Only Claude Code renews it, and only
        /// when it runs, so this says nothing about the account.
        case tokenStale
        /// Anthropic refused a token that had not lapsed yet — a different
        /// problem, and one running `claude` will not fix.
        case unauthorized
        case httpStatus(Int)
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Not signed in to Claude Code"
            case .keychainRefused(let detail):
                return detail.isEmpty ? "Keychain access denied" : "Keychain: \(detail)"
            case .credentialsUnreadable:
                return "Could not read credentials"
            case .tokenStale:
                return "Token expired — run claude once to renew it"
            case .unauthorized:
                return "Anthropic rejected the token (401)"
            case .rateLimited:
                return "Rate limited — showing last reading"
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
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                               encoding: .utf8) ?? ""
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            guard let blob = try? JSONDecoder().decode(CredentialBlob.self, from: data) else {
                throw ProviderError.credentialsUnreadable
            }
            return blob.claudeAiOauth
        }

        // Not every install keeps the token in the keychain, so a miss is not
        // yet an answer — the file is the other place Claude Code writes it.
        if let fileData = try? Data(contentsOf: credentialsFile) {
            guard let blob = try? JSONDecoder().decode(CredentialBlob.self, from: fileData) else {
                throw ProviderError.credentialsUnreadable
            }
            return blob.claudeAiOauth
        }

        // 44 is the only status that means "no such item"; everything else is
        // the keychain saying no, and the reason matters.
        if process.terminationStatus == 44 {
            throw ProviderError.notSignedIn
        }
        throw ProviderError.keychainRefused(cleanUp(errorText))
    }

    /// `security: SecKeychainSearchCopyNext: <message>` — only the message is
    /// worth putting in front of anyone.
    private static func cleanUp(_ text: String) -> String {
        text.split(separator: "\n").first.map {
            $0.split(separator: ":").dropFirst(2).joined(separator: ":")
              .trimmingCharacters(in: .whitespaces)
        } ?? ""
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

        /// Per-model allowances arrive here rather than as named top-level
        /// fields, with the model in `scope`. Parsed generically so a change of
        /// model needs no code change.
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let display_name: String? }
                let model: Model?
            }
            let kind: String?
            let percent: Double?
            let resets_at: String?
            let scope: Scope?
        }
        let limits: [Limit]?
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

    /// Seconds to wait before each retry of a throttled request.
    private static let retryBackoff: [Double] = [3, 8, 20]

    /// Returns the first non-429 response, or the last 429 if all attempts are
    /// refused.
    private static func fetchWithRetry(_ request: URLRequest) async throws -> (Data, Int) {
        var last: (Data, Int) = (Data(), 0)
        for attempt in 0...retryBackoff.count {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(retryBackoff[attempt - 1]))
            }
            let (body, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            last = (body, code)
            if code != 429 { return last }
        }
        return last
    }

    static func fetch() async -> ProviderUsage {
        var result = ProviderUsage(provider: .claude)
        do {
            let creds = try loadCredentials()
            result.plan = creds.subscriptionType

            // Only Claude Code renews this, and only while it runs — a few
            // hours after its last use the token is dead. Saying so beats
            // firing a request we already know will come back 401.
            if let expiresAt = creds.expiresAt,
               Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
                throw ProviderError.tokenStale
            }

            var request = URLRequest(url: usageEndpoint)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.timeoutInterval = 15

            // This endpoint throttles hard and erratically: six calls spaced
            // three seconds apart were measured as 200, 429, 429, 200, 429,
            // 429. A single 429 predicts nothing about the next attempt, and
            // the server's own `retry-after: 0` is no help, so back off on our
            // own schedule instead of surfacing the first refusal.
            //
            // The delays total roughly half a minute, which stays inside even
            // the shortest refresh interval on offer.
            let (data, code) = try await fetchWithRetry(request)

            guard code == 200 else {
                switch code {
                case 401: throw ProviderError.unauthorized
                // UsageStore keeps the last good reading behind the error, so
                // being throttled costs the numbers nothing.
                case 429: throw ProviderError.rateLimited
                default: throw ProviderError.httpStatus(code)
                }
            }

            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            result.session = window(from: decoded.five_hour)
            result.weekly = window(from: decoded.seven_day)

            if let scoped = decoded.limits?.first(where: {
                $0.kind == "weekly_scoped" && $0.scope?.model?.display_name != nil
            }), let used = scoped.percent {
                result.modelScoped = UsageWindow(usedPercent: used,
                                                 resetsAt: parseDate(scoped.resets_at))
                result.modelScopedName = scoped.scope?.model?.display_name
            }
        } catch {
            result.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        return result
    }
}
