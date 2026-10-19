// Draws the landing page's link preview (site/og.png, 1200 × 630) and its
// Apple touch icon (site/apple-touch-icon.png, 180 × 180) from the app icon.
// Run: swift scripts/make-share-image.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let site = root.appendingPathComponent("site")
let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon-1024.png"))!

let paper = NSColor(red: 0.98, green: 0.976, blue: 0.969, alpha: 1)
let ink = NSColor(red: 0.11, green: 0.098, blue: 0.086, alpha: 1)
let muted = NSColor(red: 0.43, green: 0.40, blue: 0.376, alpha: 1)
let line = NSColor(red: 0.11, green: 0.098, blue: 0.086, alpha: 0.09)
let orange = NSColor(red: 250 / 255, green: 93 / 255, blue: 0, alpha: 1)

func png(width: Int, height: Int, scale: CGFloat = 1, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(width) * scale), pixelsHigh: Int(CGFloat(height) * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0, mono: Bool = false) -> NSAttributedString {
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
}

let og = png(width: 1200, height: 630) { bounds in
    paper.setFill()
    bounds.fill()

    // A slice of the menu bar across the top, with the running timer in it.
    let bar = NSRect(x: 0, y: bounds.height - 64, width: bounds.width, height: 64)
    NSColor.white.withAlphaComponent(0.6).setFill()
    bar.fill()
    line.setFill()
    NSRect(x: 0, y: bar.minY, width: bounds.width, height: 2).fill()
    let square = NSRect(x: 820, y: bar.midY - 14, width: 40, height: 28)
    orange.setFill()
    NSBezierPath(roundedRect: square, xRadius: 7, yRadius: 7).fill()
    NSColor.white.setFill()
    for x in [square.midX - 7, square.midX + 2.5] {
        NSBezierPath(roundedRect: NSRect(x: x, y: square.midY - 7, width: 4.5, height: 14), xRadius: 1, yRadius: 1).fill()
    }
    text("1:24", size: 26, weight: .medium, color: ink, mono: true).draw(at: NSPoint(x: 874, y: bar.midY - 16))
    text("Design", size: 26, weight: .medium, color: ink).draw(at: NSPoint(x: 940, y: bar.midY - 16))
    text("Mon 9:41", size: 26, weight: .medium, color: ink).draw(at: NSPoint(x: 1060, y: bar.midY - 16))

    // The pitch, left; the icon, right.
    let left: CGFloat = 80
    text("Harvestbeam", size: 30, weight: .semibold, color: muted).draw(at: NSPoint(x: left, y: 404))
    text("A better Harvest", size: 92, weight: .bold, color: ink, kern: -3.2).draw(at: NSPoint(x: left - 4, y: 290))
    text("timer for Mac", size: 92, weight: .bold, color: ink, kern: -3.2).draw(at: NSPoint(x: left - 4, y: 186))
    text("Press ⌥H anywhere. Type. Press Return. Free for macOS 14+.", size: 28, weight: .regular, color: muted)
        .draw(at: NSPoint(x: left, y: 110))
    icon.draw(in: NSRect(x: 850, y: 120, width: 300, height: 300))
}
try og.write(to: site.appendingPathComponent("og.png"))

// iOS draws its own rounded corners, so the touch icon is the full orange tile.
let touch = png(width: 180, height: 180) { bounds in
    orange.setFill()
    bounds.fill()
    icon.draw(in: bounds.insetBy(dx: -180 * 100 / 824, dy: -180 * 100 / 824))
}
try touch.write(to: site.appendingPathComponent("apple-touch-icon.png"))
print("Wrote site/og.png and site/apple-touch-icon.png")
