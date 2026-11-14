// Usage data: where the numbers come from and how they're parsed.
import Foundation

struct Limit: Equatable {
    let label: String
    let used: Double          // percent used, 0...100
    let resets: Date?
    let modelScoped: Bool     // e.g. a model-only weekly cap; doesn't stop the whole account
    var remaining: Double { max(0, min(100, 100 - used)) }
}

struct Reading { let limits: [Limit]; let fetched: Date }

struct UsageError: Error { let text: String }

enum Source: String, CaseIterable, Identifiable {
    case claudeCode = "claudeCode"   // the Claude Code login on this Mac (Keychain or ~/.claude/.credentials.json)
    case command = "command"         // any shell command that prints a token or usage JSON
    var id: String { rawValue }
    var title: String { self == .claudeCode ? "Claude Code login on this Mac" : "Custom command" }
}

enum UsageAPI {
    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(settings s: Settings) -> Result<Reading, UsageError> {
        switch s.source {
        case .claudeCode:
            switch ClaudeCodeToken.read() {
            case .failure(let e): return .failure(e)
            case .success(let t): return fromToken(t, timeout: s.requestTimeout)
            }
        case .command:
            let cmd = s.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if cmd.isEmpty { return .failure(UsageError(text: "No command set (Settings > Source)")) }
            switch Shell.run(cmd, timeout: s.requestTimeout + 30) {
            case .failure(let e): return .failure(e)
            case .success(let out):
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") { return parse(Data(trimmed.utf8)) }
                if trimmed.hasPrefix("sk-ant-") { return fromToken(trimmed, timeout: s.requestTimeout) }
                return .failure(UsageError(text: "Command printed neither a token nor usage JSON"))
            }
        }
    }

    static func fromToken(_ token: String, timeout: Double) -> Result<Reading, UsageError> {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude-usage-meter/1.0", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Reading, UsageError> = .failure(UsageError(text: "No response"))
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err = err { result = .failure(UsageError(text: err.localizedDescription)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                result = .failure(UsageError(text: "Login rejected (HTTP \(code)). Run `claude` once to refresh it."))
                return
            }
            guard code == 200, let data = data else { result = .failure(UsageError(text: "HTTP \(code)")); return }
            result = parse(data)
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 5)
        return result
    }

    /// Accepts Anthropic's usage JSON, or the `hermes usage --json` shape ({"windows":[{label, used_percent, resets_at}]}).
    static func parse(_ data: Data) -> Result<Reading, UsageError> {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(UsageError(text: "Unreadable usage data"))
        }
        if let why = obj["unavailable_reason"] as? String, !why.isEmpty { return .failure(UsageError(text: why)) }
        var limits: [Limit] = []

        if let ws = obj["windows"] as? [[String: Any]] {                       // hermes shape
            for w in ws {
                guard let used = num(w["used_percent"]) else { continue }
                let label = (w["label"] as? String) ?? "Limit"
                let scoped = (w["scope"] as? String) == "model" || label.lowercased().contains("opus") || label.lowercased().contains("sonnet")
                limits.append(Limit(label: label, used: used, resets: date(w["resets_at"]), modelScoped: scoped))
            }
        } else if let ls = obj["limits"] as? [[String: Any]], !ls.isEmpty {     // current Anthropic shape
            for l in ls {
                guard let used = num(l["percent"]) else { continue }
                let kind = (l["kind"] as? String) ?? ""
                var label = kind.hasPrefix("weekly") ? "Week" : kind.hasPrefix("session") || kind.contains("five") ? "Session (5 h)" : kind.capitalized
                var scoped = false
                if let scope = l["scope"] as? [String: Any], let model = scope["model"] as? [String: Any] {
                    scoped = true
                    if let n = model["display_name"] as? String { label += " · \(n)" }
                } else if kind == "weekly_all" { label = "Week (all models)" }
                limits.append(Limit(label: label, used: used, resets: date(l["resets_at"]), modelScoped: scoped))
            }
        } else {                                                                 // older Anthropic shape
            let keys: [(String, String, Bool)] = [("five_hour", "Session (5 h)", false), ("seven_day", "Week (all models)", false),
                                                 ("seven_day_opus", "Week · Opus", true), ("seven_day_sonnet", "Week · Sonnet", true)]
            for (k, label, scoped) in keys {
                guard let w = obj[k] as? [String: Any], var used = num(w["utilization"]) else { continue }
                if used <= 1 && used > 0 && !(w["utilization"] is Int) { used *= 100 }
                limits.append(Limit(label: label, used: used, resets: date(w["resets_at"]), modelScoped: scoped))
            }
        }
        if limits.isEmpty { return .failure(UsageError(text: "No usage limits in the response")) }
        return .success(Reading(limits: limits, fetched: Date()))
    }

    private static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return a.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Reads (never refreshes or writes) Claude Code's OAuth login. Refresh tokens are single-use, so this app
/// leaves rotation to Claude Code itself; if the token has expired it says so instead.
enum ClaudeCodeToken {
    static func read() -> Result<String, UsageError> {
        var payload: [String: Any]?
        if case .success(let s) = Shell.exec("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 10),
           let d = s.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) {
            payload = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        }
        if payload == nil {
            let f = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.credentials.json")
            if let d = try? Data(contentsOf: f) { payload = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
        }
        guard let oauth = payload?["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else {
            return .failure(UsageError(text: "No Claude Code login found. Install Claude Code and sign in, or use a custom command."))
        }
        if let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue, exp / 1000 < Date().timeIntervalSince1970 {
            return .failure(UsageError(text: "Claude Code login expired. Run `claude` once to refresh it."))
        }
        return .success(token)
    }
}

enum Shell {
    /// Runs a command line through the user's login shell, so PATH matches Terminal.
    static func run(_ command: String, timeout: Double) -> Result<String, UsageError> {
        let sh = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return exec(sh, ["-l", "-c", command], timeout: timeout)
    }

    static func exec(_ path: String, _ args: [String], timeout: Double) -> Result<String, UsageError> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(UsageError(text: "Couldn't run \(path)")) }
        var data = Data()
        let reader = DispatchQueue(label: "read"); let group = DispatchGroup(); group.enter()
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate(); return .failure(UsageError(text: "Timed out after \(Int(timeout)) s"))
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 { return .failure(UsageError(text: "Command exited with \(p.terminationStatus)")) }
        return .success(String(decoding: data, as: UTF8.self))
    }
}
