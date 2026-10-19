// Draws Resources/AppIcon.icns: the Tractorbeam triangle in white on Harvest
// orange, in the standard macOS icon shape. Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path } ?? ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    // Apple's grid: an 824pt rounded square centered in 1024, corner radius ~185.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor(red: 0.96, green: 0.42, blue: 0.13, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Same orange gradient as the window's title bar.
    NSGradient(starting: NSColor(red: 0.97, green: 0.47, blue: 0.19, alpha: 1),
               ending: NSColor(red: 0.92, green: 0.30, blue: 0.14, alpha: 1))!.draw(in: shape, angle: -60)

    // The Tractorbeam triangle (26 × 22), set 8pt above the tile's center;
    // picked by eye over versions set lower.
    let width = 400 * s, height = width * 22 / 26
    let originX = 512 * s - width / 2, originY = 512 * s - height / 2 + 8 * s
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: originX + width / 2, y: originY + height))
    triangle.line(to: NSPoint(x: originX + width, y: originY))
    triangle.line(to: NSPoint(x: originX, y: originY))
    triangle.close()
    NSColor.white.setFill()
    triangle.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try render(1024).write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
print("Wrote \(output.path)")
