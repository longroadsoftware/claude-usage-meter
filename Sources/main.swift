// Claude Usage Meter: shows how much of your Claude plan's usage limit is left, in the menu bar
// (always visible) and optionally on a Dock tile. Settings window for everything tunable.
import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let s = Settings.shared
    var item: NSStatusItem!
    let tile = TileView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    var last: Reading?
    var lastError: String?
    var timer: Timer?
    var settingsWindow: NSWindow?
    var notifiedFor: Date?          // reset time we've already warned about
    var observers: [Any] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "ClaudeUsageMeter"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        applyDockVisibility()
        render()
        refresh()
        scheduleTimer()
        observers.append(s.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applyDockVisibility(); self?.render(); self?.scheduleTimer() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        if CommandLine.arguments.contains("--settings") { openSettings() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.s.source == .automatic, self.last == nil, !ClaudeLogin.isSignedIn,
                  !UserDefaults.standard.bool(forKey: "offeredSignIn") else { return }
            UserDefaults.standard.set(true, forKey: "offeredSignIn")
            self.signIn()
        }
    }

    func scheduleTimer() {
        let secs = max(60, s.refreshMinutes * 60)
        if let t = timer, t.timeInterval == secs { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func applyDockVisibility() {
        let want: NSApplication.ActivationPolicy = s.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != want { NSApp.setActivationPolicy(want) }
        if s.showInDock { NSApp.dockTile.contentView = tile } else { NSApp.dockTile.contentView = nil }
    }

    @objc func refresh() {
        let settings = s
        DispatchQueue.global(qos: .utility).async {
            let r = UsageAPI.fetch(settings: settings)
            DispatchQueue.main.async {
                switch r {
                case .success(let reading): self.last = reading; self.lastError = nil
                case .failure(let e): self.lastError = e.text
                }
                self.render()
                self.maybeNotify()
            }
        }
    }

    var isStale: Bool {
        guard let l = last else { return lastError != nil }
        return Date().timeIntervalSince(l.fetched) > s.staleMinutes * 60
    }

    // MARK: drawing

    func render() {
        let lim = last.flatMap { s.pick($0) }
        let rem = lim?.remaining
        let shown = rem.map { s.show == .remaining ? $0.rounded(.down) : (100 - $0).rounded(.up) }
        let level = rem.map { s.level(remaining: $0) }
        let color = Palette.color(level: level)
        let fraction = shown.map { $0 / 100 }
        let caption = s.show == .remaining ? "remaining" : "used"

        // menu bar
        if let b = item.button {
            let ringImg = Ring.image(size: 15, fraction: fraction, color: color, lineWidth: 2.6, dim: isStale)
            let pct = shown.map { "\(Int($0))%" } ?? "--"
            var text: String
            switch s.menuBarStyle {
            case .ringAndText, .textOnly: text = "\(s.label) \(pct) \(caption)".trimmingCharacters(in: .whitespaces)
            case .ringAndPercent: text = pct
            case .ringOnly: text = ""
            }
            if isStale && !text.isEmpty { text += " (stale)" }
            b.image = s.menuBarStyle == .textOnly ? nil : ringImg
            b.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
            var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)]
            if s.colorText, level != nil, level! > 0 { attrs[.foregroundColor] = color }
            b.attributedTitle = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: attrs)
            b.toolTip = tooltip(lim)
            b.setAccessibilityLabel("\(s.label) usage: \(pct) \(caption)")
        }

        // dock
        tile.shownPercent = shown; tile.fraction = fraction; tile.level = level
        tile.caption = caption; tile.title = s.label; tile.stale = isStale
        tile.needsDisplay = true
        if s.showInDock { NSApp.dockTile.display() }
    }

    func tooltip(_ l: Limit?) -> String {
        guard let l = l else { return lastError ?? "Checking…" }
        var t = "\(l.label): \(Int(l.remaining.rounded(.down)))% remaining, \(Int(l.used.rounded(.up)))% used"
        if let r = l.resets { t += "\nResets \(Self.when.string(from: r))" }
        return t
    }

    static let when: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE MMM d, h:mm a"; return f }()

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { let m = NSMenu(); fill(m, compact: true); return m }

    func fill(_ m: NSMenu, compact: Bool = false) {
        m.removeAllItems()
        if let rd = last {
            for l in rd.limits {
                var line = "\(l.label): \(Int(l.remaining.rounded(.down)))% remaining · \(Int(l.used.rounded(.up)))% used"
                if let r = l.resets { line += " · resets \(Self.when.string(from: r))" }
                let mi = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                if let p = s.pick(rd), p == l { mi.state = .on }
                m.addItem(mi)
            }
            let tf = DateFormatter(); tf.timeStyle = .short
            m.addItem(withTitle: "Checked at \(tf.string(from: rd.fetched))", action: nil, keyEquivalent: "")
        } else if lastError == nil {
            m.addItem(withTitle: "Checking…", action: nil, keyEquivalent: "")
        }
        if let e = lastError { m.addItem(withTitle: "Last check failed: \(e)", action: nil, keyEquivalent: "") }
        m.addItem(.separator())
        if s.source == .automatic {
            if ClaudeLogin.isSignedIn { add(m, "Sign Out of Claude", #selector(signOut)) }
            else { add(m, "Sign in with Claude…", #selector(signIn)) }
        }
        add(m, s.show == .remaining ? "Show Used Instead" : "Show Remaining Instead", #selector(toggleShown))
        add(m, "Refresh Now", #selector(refresh), "r")
        if !compact {
            add(m, "Settings…", #selector(openSettings), ",")
            m.addItem(.separator())
            add(m, "Quit Claude Usage Meter", #selector(quit), "q")
        }
    }

    func add(_ m: NSMenu, _ title: String, _ sel: Selector, _ key: String = "") {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; m.addItem(i)
    }

    @objc func signIn() {
        lastError = "Finish signing in in your browser…"; render()
        if !UserDefaults.standard.bool(forKey: "shownAccountTip") {
            UserDefaults.standard.set(true, forKey: "shownAccountTip")
            alert("Sign in with Claude",
                  "Your browser will open claude.ai. Use the Claude account that has your Pro or Max plan.\n\nIf it asks you to upgrade even though you have a plan, the browser is signed in to a different Claude account. Log out on claude.ai, sign in with the right one, and choose Sign in with Claude… again.")
        }
        SignInPrompt.run { [weak self] err in
            if let e = err { self?.lastError = e; self?.render(); self?.alert("Sign-in didn't finish", e) }
            else { self?.lastError = nil; self?.refresh() }
        }
    }
    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
    @objc func signOut() { ClaudeLogin.signOut(); last = nil; refresh() }

    @objc func toggleShown() { s.show = s.show == .remaining ? .used : .remaining }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 940),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Claude Usage Meter Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: s, refresh: { [weak self] in self?.refresh() }))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { openSettings(); return false }

    // MARK: low-usage notification

    func maybeNotify() {
        guard s.notifyBelow > 0, let rd = last, let l = s.pick(rd), l.remaining < s.notifyBelow else { return }
        let key = l.resets ?? Calendar.current.startOfDay(for: Date())
        if notifiedFor == key { return }
        notifiedFor = key
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let n = UNMutableNotificationContent()
            n.title = "\(self.s.label) usage: \(Int(l.remaining.rounded(.down)))% remaining"
            n.body = l.resets.map { "\(l.label) resets \(Self.when.string(from: $0))." } ?? l.label
            c.add(UNNotificationRequest(identifier: "low-\(key.timeIntervalSince1970)", content: n, trigger: nil))
        }
    }
}

// MARK: Settings window

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var refresh: () -> Void
    @State private var login = Settings.shared.launchAtLogin

    var body: some View {
        Form {
            Section("Data source") {
                Picker("Read usage from", selection: $settings.source) {
                    ForEach(Source.allCases) { Text($0.title).tag($0) }
                }
                if settings.source == .command {
                    TextField("Command", text: $settings.command, prompt: Text("e.g. hermes usage --provider anthropic --json"))
                        .font(.system(.body, design: .monospaced))
                    Text("The command must print either an OAuth token (sk-ant-oat…) or usage JSON.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(ClaudeLogin.isSignedIn ? "Signed in with Claude" : "Not signed in")
                        Spacer()
                        if ClaudeLogin.isSignedIn {
                            Button("Sign Out") { ClaudeLogin.signOut(); refresh() }
                        } else {
                            Button("Sign in with Claude…") { SignInPrompt.run { _ in refresh() } }
                        }
                    }
                    Text("Sign in once with your Claude account. If Claude Code is signed in on this Mac, that works too, with no sign-in needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Which limit", selection: $settings.limit) {
                    ForEach(LimitChoice.allCases) { Text($0.title).tag($0) }
                }
                Button("Check now") { refresh() }
            }
            Section("Display") {
                Picker("Show", selection: $settings.show) {
                    Text("Percent remaining").tag(ShowValue.remaining)
                    Text("Percent used").tag(ShowValue.used)
                }
                Picker("Menu bar", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                TextField("Label", text: $settings.label)
                Toggle("Color the menu bar text when low", isOn: $settings.colorText)
                Toggle("Also show a tile in the Dock", isOn: $settings.showInDock)
            }
            Section("Thresholds (percent remaining)") {
                Stepper("Orange below \(Int(settings.warnBelow))%", value: $settings.warnBelow, in: 1...99, step: 5)
                Stepper("Red below \(Int(settings.criticalBelow))%", value: $settings.criticalBelow, in: 1...99, step: 1)
                Stepper(settings.notifyBelow == 0 ? "Notification: off" : "Notify below \(Int(settings.notifyBelow))%",
                        value: $settings.notifyBelow, in: 0...99, step: 5)
            }
            Section("Timing") {
                Stepper("Refresh every \(Int(settings.refreshMinutes)) min", value: $settings.refreshMinutes, in: 1...60)
                Stepper("Mark stale after \(Int(settings.staleMinutes)) min", value: $settings.staleMinutes, in: 5...240, step: 5)
                Stepper("Request timeout \(Int(settings.requestTimeout)) s", value: $settings.requestTimeout, in: 5...120, step: 5)
                Toggle("Open at login", isOn: $login).onChange(of: login) { _, v in Settings.shared.launchAtLogin = v }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 940)
    }
}

// MARK: entry point

// `--once <png> [--used]` prints the live reading and renders the Dock tile (for testing without a screen).
// `--icon <dir> <percent>` writes the app icon PNGs.
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--once" {
    let s = Settings.shared
    let original = s.show
    if args.contains("--used") { s.show = .used } else { s.show = .remaining }
    defer { s.show = original }
    let v = TileView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
    switch UsageAPI.fetch(settings: s) {
    case .success(let r):
        for l in r.limits { print("\(l.label): used \(l.used)%, remaining \(l.remaining)%\(l.modelScoped ? " (model-only)" : "")") }
        if let l = s.pick(r) {
            print("shown limit: \(l.label)")
            let shown = s.show == .remaining ? l.remaining.rounded(.down) : (100 - l.remaining).rounded(.up)
            v.shownPercent = shown; v.fraction = shown / 100; v.level = s.level(remaining: l.remaining)
            v.caption = s.show == .remaining ? "remaining" : "used"; v.title = s.label
        }
    case .failure(let e): print("failed: \(e.text)")
    }
    try? v.png(size: 256)?.write(to: URL(fileURLWithPath: args[2]))
    s.show = original
    exit(0)
}
if args.count >= 3, args[1] == "--icon" {
    let dir = args[2]; let pct = args.count > 3 ? Double(args[3]) : nil
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                       ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                       ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
        let v = TileView(frame: .zero); v.shownPercent = pct; v.fraction = pct.map { $0 / 100 }; v.level = 0
        try? v.png(size: px)?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
