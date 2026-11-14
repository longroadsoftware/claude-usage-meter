// Splash / About window: "Free from Long Road Software". Shown on first launch, after each update,
// and from the menu (About Claude Usage Meter). Never on an ordinary login launch.
import AppKit
import SwiftUI

enum LRS {
    static let green = Color(red: 0x0f / 255, green: 0x6b / 255, blue: 0x45 / 255)
    static let greenLight = Color(red: 0x5e / 255, green: 0xc7 / 255, blue: 0x9a / 255)

    /// Plain links with a source tag so the site can tell visits came from this app. Nothing is sent by the app itself.
    static func link(_ base: String, _ content: String) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = (c.queryItems ?? []) + [
            .init(name: "utm_source", value: "claude-usage-meter"), .init(name: "utm_medium", value: "app"),
            .init(name: "utm_campaign", value: "splash"), .init(name: "utm_content", value: content),
        ]
        return c.url!
    }
    static let home = link("https://longroadsoftware.com/", "home")

    struct Product: Identifiable {
        let id: String, name: String, blurb: String, status: String?, url: URL
    }
    static let products: [Product] = [
        .init(id: "mfs", name: "MediaFlowSwift", blurb: "Footage manager for Mac, with a Windows version on the way. Import, organize and find every clip.",
              status: nil, url: link("https://mediaflowswift.com/", "mediaflowswift")),
        .init(id: "pc", name: "Proof Copy", blurb: "Copies camera cards to your drives and proves every file arrived intact.",
              status: "Coming soon", url: link("https://longroadsoftware.com/proof-copy/", "proofcopy")),
        .init(id: "cr", name: "Check & Roll", blurb: "RV departure and setup checklists for iPhone, shared with your crew.",
              status: "Coming soon", url: link("https://checkandroll.app/", "checkandroll")),
    ]
}

struct SplashView: View {
    var version: String
    var close: () -> Void
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 0) {
            // header
            VStack(spacing: 10) {
                if let img = Bundle.main.image(forResource: "lrs-logo") {
                    Image(nsImage: img).resizable().interpolation(.high).frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                Text("Claude Usage Meter").font(.system(size: 22, weight: .bold))
                Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                Text("Free, from **Long Road Software**")
                    .font(.system(size: 14))
                    .padding(.top, 2)
                Text("We build dependable apps for Mac, Windows, iPhone and more, and we give away small tools like this one. If the meter saves you from a surprise lockout, take a look at what else we make.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 26).padding(.bottom, 18)

            // products
            VStack(spacing: 8) {
                ForEach(LRS.products) { p in
                    Button { NSWorkspace.shared.open(p.url) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(p.name).font(.system(size: 13, weight: .semibold))
                                    if let s = p.status {
                                        Text(s).font(.system(size: 10, weight: .semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Capsule().fill((scheme == .dark ? LRS.greenLight : LRS.green).opacity(0.15)))
                                            .foregroundStyle(scheme == .dark ? LRS.greenLight : LRS.green)
                                    }
                                }
                                Text(p.blurb).font(.system(size: 11.5)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)

            // actions
            HStack(spacing: 10) {
                Button("Visit longroadsoftware.com") { NSWorkspace.shared.open(LRS.home) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Continue") { close() }
                    .buttonStyle(.borderedProminent).tint(LRS.green)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)

            Text("Unofficial. Not affiliated with or endorsed by Anthropic.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).padding(.bottom, 12)
        }
        .frame(width: 470)
    }
}

final class SplashController {
    static let shared = SplashController()
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    /// True on first launch and after the app is updated to a new version.
    static var shouldShowAutomatically: Bool {
        UserDefaults.standard.string(forKey: "splashShownForVersion") != version
    }

    func show(then: (() -> Void)? = nil) {
        onClose = then
        if window == nil {
            let host = NSHostingView(rootView: SplashView(version: Self.version, close: { [weak self] in self?.close() }))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.finished()
            }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func close() { window?.close() }

    private func finished() {
        UserDefaults.standard.set(Self.version, forKey: "splashShownForVersion")
        let next = onClose; onClose = nil
        next?()
    }

    /// Renders the splash to a PNG (for README screenshots and checks).
    static func renderPNG(to path: String, dark: Bool) {
        let host = NSHostingView(rootView: SplashView(version: version, close: {}).environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = host.appearance
        w.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        w.contentView = host
        host.layoutSubtreeIfNeeded(); host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let img = NSImage(size: size); img.addRepresentation(rep)
        let out = NSImage(size: size, flipped: false) { r in
            w.backgroundColor.setFill(); r.fill(); img.draw(in: r); return true
        }
        if let t = out.tiffRepresentation, let b = NSBitmapImageRep(data: t), let png = b.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
