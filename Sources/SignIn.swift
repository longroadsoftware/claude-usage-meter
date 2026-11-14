// "Sign in with Claude": the app's own login, so nobody has to find a token, file or command.
// Standard OAuth (PKCE) with Anthropic, the same flow Claude Code uses. The login is kept in this app's own
// Keychain item ("Claude Usage Meter") and refreshed by this app only, so it never touches Claude Code's login.
import AppKit
import CryptoKit
import Foundation
import Security

enum ClaudeLogin {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    static let tokenURLs = ["https://platform.claude.com/v1/oauth/token", "https://console.anthropic.com/v1/oauth/token"]
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let scopes = "org:create_api_key user:profile user:inference"   // the scope set Anthropic accepts for this client
    static let keychainService = "Claude Usage Meter"
    static let keychainAccount = "claude-oauth"

    struct Tokens: Codable { var access: String; var refresh: String; var expiresAt: Double }

    // MARK: sign-in

    private static var pending: (verifier: String, state: String)?

    /// Opens claude.ai in the browser. The page then shows a code for the user to paste back.
    static func begin() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = b64url(Data(bytes))
        let challenge = b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var sb = [UInt8](repeating: 0, count: 24); _ = SecRandomCopyBytes(kSecRandomDefault, sb.count, &sb)
        let state = b64url(Data(sb))
        pending = (verifier, state)
        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "code", value: "true"), .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"), .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
        ]
        NSWorkspace.shared.open(c.url!)
    }

    /// Finishes sign-in with the code the browser page showed ("code#state").
    static func finish(pasted: String) -> Result<Void, UsageError> {
        guard let p = pending else { return .failure(UsageError(text: "Start sign-in first")) }
        let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else { return .failure(UsageError(text: "No code pasted")) }
        let state = parts.count > 1 ? parts[1] : p.state
        if state != p.state { return .failure(UsageError(text: "That code is from a different sign-in. Try again.")) }
        let body: [String: Any] = ["grant_type": "authorization_code", "client_id": clientID, "code": code,
                                   "state": state, "redirect_uri": redirectURI, "code_verifier": p.verifier]
        switch post(body) {
        case .failure(let e): return .failure(e)
        case .success(let t): save(t); pending = nil; return .success(())
        }
    }

    // MARK: token for the usage call

    static var isSignedIn: Bool { load() != nil }

    static func token(timeout: Double) -> Result<String, UsageError> {
        guard var t = load() else { return .failure(UsageError(text: "Not signed in. Choose \"Sign in with Claude…\".")) }
        if t.expiresAt - 120 > Date().timeIntervalSince1970 { return .success(t.access) }
        switch post(["grant_type": "refresh_token", "refresh_token": t.refresh, "client_id": clientID]) {
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
            if case .failure(let e) = out { lastErr = e; if !e.text.contains("HTTP 404") { return out } }
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

/// The small "paste the code" prompt shown after the browser opens.
enum SignInPrompt {
    static func run(onDone: @escaping (String?) -> Void) {
        ClaudeLogin.begin()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Sign in with Claude"
        a.informativeText = "Your browser opened claude.ai. Approve access, then copy the code it shows and paste it here."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Paste code"
        a.accessoryView = field
        a.addButton(withTitle: "Sign In"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { onDone(nil); return }
        let code = field.stringValue
        DispatchQueue.global().async {
            let r = ClaudeLogin.finish(pasted: code)
            DispatchQueue.main.async {
                if case .failure(let e) = r { onDone(e.text) } else { onDone(nil) }
            }
        }
    }
}
