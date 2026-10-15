#if DEBUG
import AppKit
import HarvestKit
import HarvestUI
import SwiftUI

/// `HarvestBar --snapshots <dir>` renders the panel offscreen with demo data in
/// a few states and writes PNGs, for checking layout without clicking around.
/// Debug builds only.
@MainActor
enum DebugSnapshots {
    static func run(into directory: String) async {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let tracker = TimeTracker.demo()
            UserDefaults(suiteName: "HarvestBarDemo")?.removeObject(forKey: "favorites.v1")
            await tracker.refresh(force: true)
            if tracker.favorites.keys.isEmpty, let first = tracker.tasks.dropFirst(3).first, let second = tracker.tasks.dropFirst(9).first {
                tracker.favorites.toggle(first.key)
                tracker.favorites.toggle(second.key)
            }

            let window = makeWindow(RootView().environment(tracker), appearance: appearance)
            await settle()
            write(window, to: url.appendingPathComponent("1-running-\(suffix).png"))

            if let field = firstTextField(in: window.contentView!) {
                window.makeFirstResponder(field)
                field.stringValue = "des"
                field.currentEditor()?.string = "des"
                NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
                (field.currentEditor() as? NSTextView)?.didChangeText()
            }
            await settle()
            write(window, to: url.appendingPathComponent("2-search-\(suffix).png"))

            await tracker.stop()
            if let field = firstTextField(in: window.contentView!) {
                field.currentEditor()?.string = ""
                (field.currentEditor() as? NSTextView)?.didChangeText()
            }
            await settle()
            write(window, to: url.appendingPathComponent("3-idle-\(suffix).png"))

            tracker.signOut()
            await settle()
            write(window, to: url.appendingPathComponent("4-signin-\(suffix).png"))
            window.close()
        }
        UserDefaults(suiteName: "HarvestBarDemo")?.removeObject(forKey: "favorites.v1")
    }

    private static func makeWindow(_ view: some View, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -3000, y: 0, width: 380, height: 560),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .aqua ? NSColor(white: 0.97, alpha: 1) : NSColor(white: 0.16, alpha: 1)
        window.contentView = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        window.orderFrontRegardless()
        return window
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    private static func write(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, !(field is NSSecureTextField),
           (field.placeholderString ?? field.placeholderAttributedString?.string ?? "").hasPrefix("Search") {
            return field
        }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }
}
#endif
