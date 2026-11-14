// Drawing: the ring used in the menu bar, the Dock tile and the app icon.
import AppKit

enum Palette {
    static func color(level: Int?) -> NSColor {
        guard let l = level else { return .systemGray }
        return [NSColor.systemGreen, .systemOrange, .systemRed][l]
    }
}

enum Ring {
    /// A ring filled to `fraction` (0...1). `template` = monochrome for the menu bar's light/dark handling.
    static func image(size: CGFloat, fraction: Double?, color: NSColor, lineWidth: CGFloat? = nil, dim: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lw = lineWidth ?? max(1.6, size * 0.16)
            let c = NSPoint(x: rect.midX, y: rect.midY), r = size / 2 - lw / 2 - 0.5
            let track = NSBezierPath(); track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
            track.lineWidth = lw; NSColor.labelColor.withAlphaComponent(0.22).setStroke(); track.stroke()
            if let f = fraction, f > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * min(1, f), clockwise: true)
                arc.lineWidth = lw; arc.lineCapStyle = (f < 0.12 || f > 0.88) ? .butt : .round
                (dim ? color.withAlphaComponent(0.45) : color).setStroke(); arc.stroke()
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

/// The big square tile (Dock / app icon).
final class TileView: NSView {
    var shownPercent: Double?   // the number on the tile
    var fraction: Double?       // ring fill
    var level: Int?
    var caption = "remaining"
    var title = "Claude"
    var stale = false

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds.insetBy(dx: bounds.width * 0.07, dy: bounds.height * 0.07)
        let bg = NSBezierPath(roundedRect: b, xRadius: b.width * 0.22, yRadius: b.width * 0.22)
        NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.17, alpha: 1).setFill(); bg.fill()
        let c = NSPoint(x: b.midX, y: b.midY), r = b.width * 0.35, lw = b.width * 0.095
        let track = NSBezierPath(); track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = lw; NSColor(white: 1, alpha: 0.14).setStroke(); track.stroke()
        let col = Palette.color(level: level)
        if let f = fraction, f > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * min(1, f), clockwise: true)
            arc.lineWidth = lw; arc.lineCapStyle = (f < 0.12 || f > 0.88) ? .butt : .round
            (stale ? col.withAlphaComponent(0.45) : col).setStroke(); arc.stroke()
        }
        let txt = shownPercent.map { "\(Int($0))%" } ?? "--"
        let big = NSFont.systemFont(ofSize: b.width * (txt.count > 3 ? 0.2 : 0.25), weight: .bold)
        let s1 = NSAttributedString(string: txt, attributes: [.font: big, .foregroundColor: NSColor.white.withAlphaComponent(stale ? 0.6 : 1)])
        let z1 = s1.size(); s1.draw(at: NSPoint(x: c.x - z1.width / 2, y: c.y - z1.height / 2))
        let grey = NSColor(white: 1, alpha: 0.75)
        let t = String(title.prefix(10))
        let s0 = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: b.width * (t.count > 6 ? 0.078 : 0.1), weight: .semibold), .foregroundColor: grey])
        let z0 = s0.size(); s0.draw(at: NSPoint(x: c.x - z0.width / 2, y: c.y + b.width * 0.1))
        let lab = stale ? "stale" : caption
        let s2 = NSAttributedString(string: lab, attributes: [.font: NSFont.systemFont(ofSize: b.width * (lab.count > 6 ? 0.078 : 0.1), weight: .semibold), .foregroundColor: grey])
        let z2 = s2.size(); s2.draw(at: NSPoint(x: c.x - z2.width / 2, y: c.y - b.width * 0.175))
    }

    func png(size px: Int) -> Data? {
        frame = NSRect(x: 0, y: 0, width: px, height: px)
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
