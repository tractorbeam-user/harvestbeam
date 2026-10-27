// Draws the disk image window's background: Harvestbeam orange, the name in
// white, and a dotted beam from the app to Applications that ends in the
// Tractorbeam triangle. Run: swift scripts/make-dmg-background.swift <dir> [name]
// Writes background.png and background@2x.png. Finder draws icon labels black
// in Light Mode and white in Dark Mode; both read on this orange.
import AppKit

/// Window size and icon centers, in points from the top left. scripts/dmg-settings.py
/// uses the same numbers.
let window = NSSize(width: 800, height: 440)
/// Finder pins the background to the top left and never scales it, so paint
/// well past the window: resizing it shows more orange, never a white edge.
let size = NSSize(width: 1600, height: 1000)
let appCenter = NSPoint(x: 260, y: 228)
let applicationsCenter = NSPoint(x: 540, y: 228)

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
/// "Harvestbeam", or "Harvestbeam Beta" for the beta's disk image.
let appName = CommandLine.arguments.dropFirst(2).first ?? "Harvestbeam"
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Flip, so points match Finder's top-left coordinates.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)

    // The icon's gradient, with a warm light from above.
    NSGradient(starting: NSColor(red: 0.97, green: 0.47, blue: 0.19, alpha: 1),
               ending: NSColor(red: 0.90, green: 0.29, blue: 0.13, alpha: 1))!.draw(in: NSRect(origin: .zero, size: size), angle: -70)
    NSGradient(colors: [NSColor(red: 1, green: 0.82, blue: 0.6, alpha: 0.45), NSColor(red: 1, green: 0.82, blue: 0.6, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: window.width / 2, y: -40), radius: 0,
              toCenter: NSPoint(x: window.width / 2, y: -40), radius: 330, options: [])

    // Soft pools of light for the two icons to sit in.
    for center in [appCenter, applicationsCenter] {
        NSGradient(colors: [NSColor(white: 1, alpha: 0.28), NSColor(white: 1, alpha: 0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: 96, options: [])
    }

    // The name, in a serif like the welcome window's headlines.
    let serif = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .largeTitle).withDesign(.serif)
        .map { NSFont(descriptor: $0, size: 30) } ?? nil
    let title = NSAttributedString(string: appName, attributes: [
        .font: serif ?? NSFont.systemFont(ofSize: 30),
        .foregroundColor: NSColor.white,
        .kern: -0.4,
    ])
    drawFlipped(title, centeredAt: NSPoint(x: window.width / 2, y: 72))

    // The beam: dots that grow toward Applications, then the triangle,
    // turned to point the way.
    let start = appCenter.x + 78, end = applicationsCenter.x - 92
    let dots = 9
    for i in 0..<dots {
        let t = CGFloat(i) / CGFloat(dots - 1)
        let x = start + (end - start) * t
        let r = 1.8 + 1.4 * t
        NSColor(white: 1, alpha: 0.45 + 0.45 * t).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: appCenter.y - 8 - r, width: r * 2, height: r * 2)).fill()
    }
    let tip = NSPoint(x: end + 26, y: appCenter.y - 8)
    let arrow = NSBezierPath()
    arrow.move(to: tip)
    arrow.line(to: NSPoint(x: tip.x - 15, y: tip.y - 9))
    arrow.line(to: NSPoint(x: tip.x - 15, y: tip.y + 9))
    arrow.close()
    NSColor.white.setFill()
    arrow.fill()

    let caption = NSAttributedString(string: "Drag \(appName) into Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(white: 1, alpha: 0.85),
    ])
    drawFlipped(caption, centeredAt: NSPoint(x: window.width / 2, y: 384))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Text draws upside down in a flipped context; flip it back around its spot.
func drawFlipped(_ text: NSAttributedString, centeredAt point: NSPoint) {
    let textSize = text.size()
    guard let cg = NSGraphicsContext.current?.cgContext else { return }
    cg.saveGState()
    cg.translateBy(x: point.x - textSize.width / 2, y: point.y + textSize.height / 2)
    cg.scaleBy(x: 1, y: -1)
    text.draw(at: .zero)
    cg.restoreGState()
}

try render(scale: 1).write(to: directory.appendingPathComponent("background.png"))
try render(scale: 2).write(to: directory.appendingPathComponent("background@2x.png"))
print("Wrote \(directory.path)/background.png")
