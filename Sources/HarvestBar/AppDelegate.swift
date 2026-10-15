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
            button.action = #selector(togglePanel)
            button.imagePosition = .imageLeading
            button.setAccessibilityTitle("Harvest Bar")
        }

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
        poller = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.isKeyWindow else { return }
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
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentMinSize = NSSize(width: 340, height: 440)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        setKeptOnTop(UserDefaults.standard.bool(forKey: Self.keepOnTopKey))

        let actions = WindowActions(
            close: { [weak self] in self?.hidePanel() },
            snapToMenuBar: { [weak self] in self?.placeBelowStatusItem() },
            isKeptOnTop: { [weak self] in self?.panel.level == .floating },
            setKeptOnTop: { [weak self] in self?.setKeptOnTop($0) }
        )
        let host = NSHostingView(rootView: RootView().environment(tracker).environment(\.windowActions, actions))
        host.sizingOptions = []
        panel.contentView = host

        hasPlacedPanel = panel.setFrameUsingName(Self.frameName)
        panel.setFrameAutosaveName(Self.frameName)
    }

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
        NSApp.activate()
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

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let title = tracker.running.map { entry in
            " " + MenuBarDisplay.title(task: tracker.task(for: entry), notes: entry.notes, elapsed: entry.elapsed())
        } ?? ""
        guard title != lastTitle else { return }
        lastTitle = title

        if tracker.running != nil {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                .applying(.init(paletteColors: [NSColor(red: 250 / 255, green: 93 / 255, blue: 0, alpha: 1)]))
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Timer running")?
                .withSymbolConfiguration(config)
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ])
            button.toolTip = tracker.runningTask.map { "\($0.task.name) · \($0.subtitle)" }
        } else {
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
