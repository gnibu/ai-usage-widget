import Foundation

/// Reads OAuth credentials already stored on the machine by the two CLIs:
///   - Claude Code: macOS Keychain item "Claude Code-credentials"
///   - Codex:       ~/.codex/auth.json
///
/// Nothing is written back to those stores and no token is ever logged. This is
/// a direct port of `usage.py`; keep the two in step.
enum Fetcher {
    static let keychainService = "Claude Code-credentials"
    static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let codexAuthPath = ("~/.codex/auth.json" as NSString).expandingTildeInPath
    static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/codex/usage")!
    static let codexUserAgent = "codex_cli_rs/0.56.0 (Mac OS 26.4.0; arm64) Terminal"

    static let timeout: TimeInterval = 20

    static func fetchAll() async -> Report {
        async let claude = fetchClaude()
        async let codex = fetchCodex()
        return await Report(providers: [claude, codex])
    }

    // ----------------------------------------------------------------- //
    // Claude Code
    // ----------------------------------------------------------------- //

    static func fetchClaude() async -> Provider {
        var provider = Provider(name: "Claude")

        guard let blob = keychainSecret(service: keychainService) else {
            provider.error = "keychain unavailable"
            return provider
        }
        let oauth = (json(blob)?["claudeAiOauth"] as? [String: Any]) ?? [:]
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
            provider.error = "not logged in"
            return provider
        }
        provider.plan = oauth["subscriptionType"] as? String

        let data: [String: Any]
        do {
            data = try await getJSON(claudeUsageURL, headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
            ])
        } catch let error as HTTPStatus {
            provider.error = error.code == 401 ? "token expired — run claude" : "http \(error.code)"
            return provider
        } catch {
            provider.error = String(error.localizedDescription.prefix(80))
            return provider
        }

        // The endpoint reports the bucket but not its length, and both are fixed.
        for (key, label, length) in [("five_hour", "5h", 5 * 3600), ("seven_day", "week", 7 * 86400)] {
            guard let block = data[key] as? [String: Any] else { continue }
            provider.windows.append(UsageWindow(
                label: label,
                percent: (block["utilization"] as? NSNumber)?.doubleValue ?? 0,
                resetsAt: epoch(fromISO: block["resets_at"] as? String),
                windowSeconds: length
            ))
        }
        provider.ok = !provider.windows.isEmpty
        if !provider.ok { provider.error = "no limit data" }
        return provider
    }

    // ----------------------------------------------------------------- //
    // Codex
    // ----------------------------------------------------------------- //

    static func fetchCodex() async -> Provider {
        var provider = Provider(name: "Codex")

        guard let raw = FileManager.default.contents(atPath: codexAuthPath),
              let tokens = json(raw)?["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty
        else {
            provider.error = "not logged in"
            return provider
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "chatgpt-account-id": (tokens["account_id"] as? String) ?? "",
            "originator": "codex_cli_rs",
            "User-Agent": codexUserAgent,
            "Accept": "application/json",
        ]

        let data: [String: Any]
        do {
            do {
                data = try await getJSON(codexUsageURL, headers: headers)
            } catch let error as HTTPStatus where error.code == 403 {
                // The edge in front of chatgpt.com occasionally answers 403 to
                // an otherwise valid request; one retry clears it.
                try await Task.sleep(nanoseconds: 2_000_000_000)
                data = try await getJSON(codexUsageURL, headers: headers)
            }
        } catch let error as HTTPStatus {
            provider.error = error.code == 401 ? "token expired — run codex" : "http \(error.code)"
            return provider
        } catch {
            provider.error = String(error.localizedDescription.prefix(80))
            return provider
        }

        provider.plan = data["plan_type"] as? String
        provider.windows += codexWindows(data["rate_limit"])

        // Model-specific buckets (e.g. GPT-5.3-Codex-Spark) live in their own
        // list and are billed separately from the main quota.
        for extra in (data["additional_rate_limits"] as? [[String: Any]]) ?? [] {
            let name = (extra["limit_name"] as? String) ?? "extra"
            let short = (name.split(separator: "-").last.map(String.init) ?? name).lowercased()
            provider.windows += codexWindows(extra["rate_limit"], prefix: "\(short) ")
        }

        provider.ok = !provider.windows.isEmpty
        if !provider.ok { provider.error = "no limit data" }
        return provider
    }

    /// Turn one Codex rate_limit block into rows, shortest window first.
    private static func codexWindows(_ limits: Any?, prefix: String = "") -> [UsageWindow] {
        guard let limits = limits as? [String: Any] else { return [] }
        var out: [UsageWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let block = limits[key] as? [String: Any] else { continue }
            let length = (block["limit_window_seconds"] as? NSNumber)?.intValue
            out.append(UsageWindow(
                label: prefix + windowLabel(length),
                percent: (block["used_percent"] as? NSNumber)?.doubleValue ?? 0,
                resetsAt: (block["reset_at"] as? NSNumber)?.intValue,
                windowSeconds: length
            ))
        }
        return out.sorted { ($0.windowSeconds ?? 0) < ($1.windowSeconds ?? 0) }
    }

    // ----------------------------------------------------------------- //
    // plumbing
    // ----------------------------------------------------------------- //

    struct HTTPStatus: Error {
        let code: Int
    }

    private static func getJSON(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw HTTPStatus(code: status)
        }
        return json(data) ?? [:]
    }

    private static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Shelled out rather than done through SecItemCopyMatching: `security` is
    /// what the Python version uses, and it keeps the app out of the
    /// keychain-entitlement business. macOS asks for consent the first time.
    private static func keychainSecret(service: String) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? out : nil
    }

    private static func epoch(fromISO value: String?) -> Int? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return Int(date.timeIntervalSince1970) }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return Int(date.timeIntervalSince1970) }
        return nil
    }

    private static func windowLabel(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "limit" }
        if seconds >= 7 * 86400 { return "week" }
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        return "\(seconds / 3600)h"
    }
}
