// "Sign in with Claude": the app's own login, so nobody has to find a token, file or command.
// Standard OAuth (PKCE) with Anthropic, the same flow Claude Code uses. The login is kept in this app's own
// Keychain item ("Claude Usage Meter") and refreshed by this app only, so it never touches Claude Code's login.
import AppKit
import CryptoKit
import Foundation
import Security

enum ClaudeLogin {
    // Mirrors Claude Code's own login (claude.com authorize page, platform.claude.com token host, loopback redirect).
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.com/cai/oauth/authorize"
    static let tokenURLs = ["https://platform.claude.com/v1/oauth/token"]
    static let successURL = "https://platform.claude.com/oauth/code/success?app=claude-code"
    static let scopeList = ["org:create_api_key", "user:profile", "user:inference", "user:sessions:claude_code",
                            "user:mcp_servers", "user:file_upload"]
    static var scopes: String { scopeList.joined(separator: " ") }
    static let keychainService = "Claude Usage Meter"
    static let keychainAccount = "claude-oauth"

    struct Tokens: Codable { var access: String; var refresh: String; var expiresAt: Double }

    // MARK: sign-in

    /// Opens claude.com in the browser and waits for it to hand the code back to a one-time local listener
    /// on 127.0.0.1. No copy and paste. Calls `done` on the main queue with nil on success or an error message.
    static func signIn(done: @escaping (String?) -> Void) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = b64url(Data(bytes))
        let challenge = b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var sb = [UInt8](repeating: 0, count: 24); _ = SecRandomCopyBytes(kSecRandomDefault, sb.count, &sb)
        let state = b64url(Data(sb))

        let server = LoopbackServer(); LoopbackServer.active = server
        guard let port = server.start() else { DispatchQueue.main.async { done("Couldn't open a local port for sign-in") }; return }
        let redirect = "http://localhost:\(port)/callback"
        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "code", value: "true"), .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"), .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: scopes), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
        ]
        server.onRequest = { query in
            let q = Dictionary(uniqueKeysWithValues: (URLComponents(string: "http://x/?" + query)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let err = q["error"] { return (nil, "Sign-in was cancelled (\(err)).") }
            guard q["state"] == state, let code = q["code"], !code.isEmpty else { return (nil, "Sign-in response didn't match. Try again.") }
            let body: [String: Any] = ["grant_type": "authorization_code", "client_id": clientID, "code": code,
                                       "state": state, "redirect_uri": redirect, "code_verifier": verifier]
            switch post(body) {
            case .failure(let e): return (nil, e.text)
            case .success(let t): save(t); return (successURL, nil)
            }
        }
        server.onFinish = { err in DispatchQueue.main.async { done(err) } }
        server.timeout(after: 300)
        NSWorkspace.shared.open(c.url!)
    }

    // MARK: token for the usage call

    static var isSignedIn: Bool { load() != nil }

    static func token(timeout: Double) -> Result<String, UsageError> {
        guard var t = load() else { return .failure(UsageError(text: "Not signed in. Choose \"Sign in with Claude…\".")) }
        if t.expiresAt - 120 > Date().timeIntervalSince1970 { return .success(t.access) }
        switch post(["grant_type": "refresh_token", "refresh_token": t.refresh, "client_id": clientID, "scope": scopes]) {
        case .failure(let e):
            if e.text.contains("invalid_grant") { signOut(); return .failure(UsageError(text: "Sign-in expired. Sign in again.")) }
            return .failure(e)
        case .success(let n):
            t = n; save(t); return .success(t.access)
        }
    }

    static func signOut() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService,
                       kSecAttrAccount: keychainAccount] as CFDictionary)
    }

    // MARK: plumbing

    private static func post(_ body: [String: Any]) -> Result<Tokens, UsageError> {
        var lastErr = UsageError(text: "Couldn't reach Anthropic")
        for u in tokenURLs {
            var req = URLRequest(url: URL(string: u)!, timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("axios/1.7.9", forHTTPHeaderField: "User-Agent")   // the token host rejects browser-like agents
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            let sem = DispatchSemaphore(value: 0)
            var out: Result<Tokens, UsageError> = .failure(lastErr)
            URLSession.shared.dataTask(with: req) { data, resp, err in
                defer { sem.signal() }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard err == nil, let data = data,
                      let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    out = .failure(UsageError(text: err?.localizedDescription ?? "HTTP \(code)")); return
                }
                guard code == 200, let a = j["access_token"] as? String else {
                    let why = (j["error"] as? String) ?? (j["error_description"] as? String) ?? "HTTP \(code)"
                    out = .failure(UsageError(text: "Sign-in failed: \(why)")); return
                }
                let exp = Date().timeIntervalSince1970 + ((j["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
                out = .success(Tokens(access: a, refresh: (j["refresh_token"] as? String) ?? (body["refresh_token"] as? String ?? ""), expiresAt: exp))
            }.resume()
            _ = sem.wait(timeout: .now() + 25)
            if case .success = out { return out }
            if case .failure(let e) = out { lastErr = e }
        }
        return .failure(lastErr)
    }

    private static func save(_ t: Tokens) {
        guard let data = try? JSONEncoder().encode(t) else { return }
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: keychainAccount]
        if SecItemUpdate(q as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var add = q; add[kSecValueData] = data; add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func load() -> Tokens? {
        var out: CFTypeRef?
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService,
                                  kSecAttrAccount: keychainAccount, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: d)
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One-shot HTTP listener on 127.0.0.1 that catches the browser's redirect back from claude.com.
final class LoopbackServer {
    var onRequest: ((String) -> (redirect: String?, error: String?))?
    var onFinish: ((String?) -> Void)?
    private var fd: Int32 = -1
    private var finished = false
    private let lock = NSLock()

    func start() -> UInt16? {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
        guard ok, listen(fd, 4) == 0 else { close(fd); return nil }
        var bound = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        let port = UInt16(bigEndian: bound.sin_port)
        DispatchQueue.global(qos: .userInitiated).async { [self] in acceptLoop() }
        return port
    }

    func timeout(after secs: Double) {
        DispatchQueue.global().asyncAfter(deadline: .now() + secs) { [weak self] in
            self?.finish("Sign-in timed out. Try again.")
        }
    }

    private func acceptLoop() {
        while true {
            let c = accept(fd, nil, nil)
            if c < 0 { return }                       // socket closed
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(c, &buf, buf.count)
            let req = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
            let line = req.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[1].hasPrefix("/callback") else {
                respond(c, status: "404 Not Found", body: "Not found"); continue
            }
            let target = String(parts[1])
            let query = target.contains("?") ? String(target.split(separator: "?", maxSplits: 1)[1]) : ""
            let (redirect, error) = onRequest?(query) ?? (nil, "Not ready")
            if let r = redirect {
                write(c, "HTTP/1.1 302 Found\r\nLocation: \(r)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                close(c)
            } else {
                respond(c, status: "200 OK", body: "<html><body style='font:16px -apple-system;padding:40px'><h2>Sign-in didn't finish</h2><p>\(error ?? "")</p><p>You can close this tab and try again from the menu bar.</p></body></html>", html: true)
            }
            finish(error)
            return
        }
    }

    private func respond(_ c: Int32, status: String, body: String, html: Bool = false) {
        let b = Array(body.utf8)
        write(c, "HTTP/1.1 \(status)\r\nContent-Type: \(html ? "text/html" : "text/plain"); charset=utf-8\r\nContent-Length: \(b.count)\r\nConnection: close\r\n\r\n\(body)")
        close(c)
    }
    private func write(_ c: Int32, _ s: String) { let a = Array(s.utf8); _ = a.withUnsafeBufferPointer { Darwin.write(c, $0.baseAddress, a.count) } }

    private func finish(_ err: String?) {
        lock.lock(); defer { lock.unlock() }
        if finished { return }
        finished = true
        if fd >= 0 { close(fd); fd = -1 }
        onFinish?(err)
        LoopbackServer.active = nil
    }

    static var active: LoopbackServer?   // keeps the listener alive until it finishes
}

/// Starts sign-in from the menu or Settings. The browser does the rest.
enum SignInPrompt {
    static func run(onDone: @escaping (String?) -> Void) {
        ClaudeLogin.signIn(done: onDone)
    }
}
