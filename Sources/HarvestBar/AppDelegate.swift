import AppKit
import HarvestKit
import HarvestUI
import SwiftUI

/// Owns the menu bar item and the tracker window. The item shows a clock when
/// idle and an orange dot with the elapsed time while a timer runs. The window
/// opens below the item the first time, then stays wherever you drag it, at
/// whatever size you leave it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let tracker: TimeTracker
    private var statusItem: NSStatusItem!
    /// Harvest-style play/pause square drawn over the item's image spot.
    /// `statusItemClicked` checks whether the click landed on it.
    private let controlButton = NSImageView()
    private var panel: TrackerPanel!
    private var hotKey: HotKey?
    private var ticker: Timer?
    private var poller: Timer?
    private var lastTitle: String?
    private var hasPlacedPanel = false

    private static let frameName = "HarvestBarWindow"
    private static let keepOnTopKey = "keepOnTop"

    init(tracker: TimeTracker) {
        self.tracker = tracker
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDisplay.register()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityTitle("Harvest Bar")
        }
        controlButton.isHidden = true
        statusItem.button?.addSubview(controlButton)

        installMainMenu()
        makePanel()

        hotKey = HotKey { [weak self] in self?.togglePanel() }
        #if DEBUG
        FileHandle.standardError.write(Data("⌥H shortcut mode: \(hotKey!.mode)\n".utf8))
        #endif

        // Keep the menu bar clock ticking, and pick up timers started on the web
        // or on another device.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusItem() }
        }
        // Pick up timers started or stopped in Harvest's own apps.
        poller = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.tracker.refresh(force: true) }
            }
        }
        updateStatusItem()

        Task {
            await tracker.refresh(force: true)
            // First run: open the window so there's somewhere to paste a token.
            if tracker.phase == .signedOut || tracker.isDemo { showPanel() }
        }
    }

    // MARK: Menu

    /// A menu bar app has no visible menus, but text fields still look up
    /// ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z through the main menu, so give it one.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Harvest Bar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Harvest Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: Window

    private func makePanel() {
        panel = TrackerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Harvest Bar"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        // An empty compact toolbar makes the title bar a little taller, with
        // the traffic lights centered in it; SwiftUI draws the bar itself.
        panel.toolbar = NSToolbar(identifier: "TitleBar")
        panel.toolbarStyle = .unifiedCompact
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentMinSize = NSSize(width: 340, height: 440)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        setKeptOnTop(UserDefaults.standard.bool(forKey: Self.keepOnTopKey))

        let actions = WindowActions(
            close: { [weak self] in self?.hidePanel() },
            snapToMenuBar: { [weak self] in self?.placeBelowStatusItem() },
            isKeptOnTop: { [weak self] in self?.panel.level == .floating },
            setKeptOnTop: { [weak self] in self?.setKeptOnTop($0) },
            setTitle: { [weak self] in self?.panel.title = $0 }
        )
        let host = NSHostingView(rootView: RootView().environment(tracker).environment(\.windowActions, actions))
        host.sizingOptions = []
        panel.contentView = host

        hasPlacedPanel = panel.setFrameUsingName(Self.frameName)
        panel.setFrameAutosaveName(Self.frameName)
    }

    /// The menu bar icon opens the window, or hides it whenever it's showing,
    /// even if another app is in front.
    @objc func controlClicked() {
        Task {
            if tracker.running != nil { await tracker.pause() } else { await tracker.resume() }
            lastTitle = nil
            updateStatusItem()
        }
    }

    @objc func statusItemClicked() {
        // Status bar clicks report the item's center as their location, so use
        // the pointer's real screen position to tell a click on the square.
        if let button = statusItem.button, let window = button.window, !controlButton.isHidden,
           NSApp.currentEvent?.type != .rightMouseUp {
            let point = button.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            if controlButton.frame.insetBy(dx: -4, dy: -6).contains(point) {
                controlClicked()
                return
            }
        }
        if panel.isVisible && !panel.isMiniaturized {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// ⌥H: bring the window forward, or hide it if it's already focused.
    @objc func togglePanel() {
        if panel.isVisible && panel.isKeyWindow && NSApp.isActive {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        if !hasPlacedPanel {
            placeBelowStatusItem()
            hasPlacedPanel = true
        }
        NSApp.unhide(nil)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        // A menu bar app isn't the active app when you click its icon, and
        // macOS's polite activate() can leave the window behind others. Force
        // it to the front, above every other app's windows.
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        tracker.didAppear()
    }

    func hidePanel() {
        panel.orderOut(nil)
        tracker.errorMessage = nil
        // Hand focus straight back to whatever you were working in.
        NSApp.hide(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    private func placeBelowStatusItem() {
        let size = panel.frame.size
        let anchor = statusItem.button?.window?.frame
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var x: CGFloat
        if let anchor, anchor.width > 0, visible.insetBy(dx: -1, dy: -40).intersects(anchor) {
            x = anchor.midX - size.width / 2
        } else {
            x = visible.maxX - size.width - 12
        }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = visible.maxY - size.height - 8
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: panel.isVisible)
    }

    private func setKeptOnTop(_ onTop: Bool) {
        panel.level = onTop ? .floating : .normal
        UserDefaults.standard.set(onTop, forKey: Self.keepOnTopKey)
    }

    // MARK: Status item

    private static let controlWidth: CGFloat = 22
    private static let orange = NSColor(red: 250 / 255, green: 93 / 255, blue: 0, alpha: 1)

    /// Harvest's menu bar control: a filled square with pause, orange while a
    /// timer runs; gray with play when paused. Orange only ever means active.
    private static func controlImage(running: Bool) -> NSImage {
        let size = NSSize(width: controlWidth, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            (running ? orange : NSColor(white: 0.5, alpha: 0.85)).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 0.5), xRadius: 4, yRadius: 4).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .black)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: running ? "pause.fill" : "play.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let g = glyph.size
                glyph.draw(in: NSRect(x: (rect.width - g.width) / 2 + (running ? 0 : 0.5),
                                      y: (rect.height - g.height) / 2, width: g.width, height: g.height))
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = running ? "Pause timer" : "Resume timer"
        return image
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let paused = tracker.pausedEntry
        let title: String
        if let entry = tracker.running {
            title = " " + MenuBarDisplay.title(task: tracker.task(for: entry), notes: entry.notes, elapsed: entry.elapsed())
        } else if let paused {
            title = " " + TimeFormat.hoursMinutes(paused.elapsed())
        } else {
            title = ""
        }
        let key = "\(tracker.running != nil)|\(paused?.id ?? 0)|\(title)"
        guard key != lastTitle else { return }
        lastTitle = key

        if tracker.running != nil || paused != nil {
            let running = tracker.running != nil
            // A clear placeholder reserves the square's spot; the button sits on it.
            button.image = NSImage(size: NSSize(width: Self.controlWidth, height: 16))
            controlButton.image = Self.controlImage(running: running)
            controlButton.toolTip = running ? "Pause timer" : "Resume timer"
            controlButton.isHidden = false
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                // No custom color: the menu bar's own text color stays legible on
                // any wallpaper.
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ])
            let task = (tracker.running ?? paused).map { tracker.task(for: $0) }
            button.toolTip = task.map { "\($0.task.name) · \($0.subtitle)" }
            button.layoutSubtreeIfNeeded()
            if let cell = button.cell as? NSButtonCell {
                controlButton.frame = cell.imageRect(forBounds: button.bounds)
            }
        } else {
            controlButton.isHidden = true
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Harvest Bar")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Harvest Bar (⌥H)"
        }
    }
}

/// A utility window that can take keyboard focus for the search field.
final class TrackerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

