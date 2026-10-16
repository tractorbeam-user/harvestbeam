import AppKit
import HarvestKit
import HarvestUI
import SwiftUI
import UserNotifications

/// Owns the menu bar item and the tracker window. The item shows a clock when
/// idle and an orange dot with the elapsed time while a timer runs. The window
/// opens below the item the first time, then stays wherever you drag it, at
/// whatever size you leave it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private let tracker: TimeTracker
    private var statusItem: NSStatusItem!
    /// Harvest-style play/pause square drawn over the item's image spot.
    /// `statusItemClicked` checks whether the click landed on it.
    private let controlButton = NSImageView()
    private var panel: TrackerPanel!
    private var hotKey: HotKey?
    private var reminders: Reminders?
    private lazy var preferences = PreferencesWindowController(tracker: tracker) { [weak self] in
        self?.resetPanelSize()
    }
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
        // A fixed name, so macOS remembers this item's place and visibility by
        // it rather than by creation order.
        statusItem.autosaveName = "HarvestbeamTimer"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityTitle("Harvestbeam")
        }
        controlButton.isHidden = true
        statusItem.button?.addSubview(controlButton)

        installMainMenu()
        makePanel()

        Prefs.register()
        Prefs.applyDockVisibility()
        registerHotKey()
        NotificationCenter.default.addObserver(forName: .toggleShortcutChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        }
        Notifier.setDelegate(self)
        reminders = Reminders(tracker: tracker) { [weak self] idle in self?.askAboutIdleTime(idle) }

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
        appMenu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Harvestbeam", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Harvestbeam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        windowMenu.addItem(withTitle: "Reset Window Size", action: #selector(resetPanelSize), keyEquivalent: "0")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: Window

    private func makePanel() {
        panel = TrackerPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Harvestbeam"
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
        // .fullScreenNone makes the green button zoom instead of going full screen.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .fullScreenNone]
        panel.delegate = self
        setKeptOnTop(UserDefaults.standard.bool(forKey: Self.keepOnTopKey))

        let actions = WindowActions(
            close: { [weak self] in self?.hidePanel() },
            snapToMenuBar: { [weak self] in self?.placeBelowStatusItem() },
            resetSize: { [weak self] in self?.resetPanelSize() },
            isKeptOnTop: { [weak self] in self?.panel.level == .floating },
            setKeptOnTop: { [weak self] in self?.setKeptOnTop($0) },
            setTitle: { [weak self] in self?.panel.title = $0 }
        )
        var windowActions = actions
        windowActions.openPreferences = { [weak self] in self?.showPreferences() }
        let host = NSHostingView(rootView: RootView().environment(tracker).environment(\.windowActions, windowActions))
        host.sizingOptions = []
        panel.contentView = host

        hasPlacedPanel = panel.setFrameUsingName(Self.frameName)
        panel.setFrameAutosaveName(Self.frameName)
    }

    /// The menu bar icon opens the window, or hides it whenever it's showing,
    /// even if another app is in front.
    @objc func controlClicked() {
        // Nothing to pause or resume: open the window to pick something.
        guard tracker.running != nil || tracker.pausedEntry != nil else {
            showPanel()
            return
        }
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

    static let defaultSize = NSSize(width: 440, height: 680)

    @objc func showPreferences() {
        preferences.show()
    }

    /// (Re)registers the show/hide shortcut from preferences; none if cleared.
    private func registerHotKey() {
        hotKey?.invalidate()
        hotKey = HotKey.Shortcut.load().map { shortcut in
            HotKey(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers) { [weak self] in self?.togglePanel() }
        }
    }

    /// Back from being away with a timer running: keep the time, or take it off.
    private func askAboutIdleTime(_ seconds: TimeInterval) {
        guard let entry = tracker.running else { return }
        let task = tracker.task(for: entry)
        let alert = NSAlert()
        alert.messageText = "You were away for \(TimeFormat.hoursMinutes(seconds))"
        alert.informativeText = "\(task.project.name) · \(task.task.name) kept running while you were away."
        alert.addButton(withTitle: "Remove Time and Keep Going")
        alert.addButton(withTitle: "Remove Time and Stop")
        alert.addButton(withTitle: "Keep Time")
        alert.icon = NSApp.applicationIconImage
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await tracker.removeIdleTime(seconds, keepRunning: true) }
        case .alertSecondButtonReturn: Task { await tracker.removeIdleTime(seconds, keepRunning: false) }
        default: break
        }
    }

    // MARK: Notifications

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { showPanel() }
    }

    /// Back to the default size, keeping the window's top-left corner put.
    @objc func resetPanelSize() {
        let content = panel.frameRect(forContentRect: NSRect(origin: .zero, size: Self.defaultSize)).size
        var frame = panel.frame
        frame.origin.y += frame.height - content.height
        frame.size = content
        panel.setFrame(frame, display: true, animate: true)
    }

    /// The green button toggles between your size and a roomier one: wide
    /// enough for four columns of tiles and as tall as fits, never full screen.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let visible = window.screen?.visibleFrame ?? newFrame
        let size = NSSize(width: min(780, visible.width - 40), height: min(940, visible.height - 40))
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        // Keep it on screen.
        frame.origin.x = min(max(frame.origin.x, visible.minX + 20), visible.maxX - size.width - 20)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 20), visible.maxY - size.height)
        return frame
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
            // Nothing tracked yet today: the gray square and today's 0:00.
            title = " " + TimeFormat.hoursMinutes(tracker.todaySeconds())
        }
        let ready = tracker.phase == .ready
        let key = "\(ready)|\(tracker.running != nil)|\(paused?.id ?? 0)|\(title)"
        guard key != lastTitle else { return }
        lastTitle = key

        if ready {
            let running = tracker.running != nil
            // A clear placeholder reserves the square's spot; the button sits on it.
            button.image = NSImage(size: NSSize(width: Self.controlWidth, height: 16))
            controlButton.image = Self.controlImage(running: running)
            controlButton.toolTip = running ? "Pause timer" : paused != nil ? "Resume timer" : "Start a timer"
            controlButton.isHidden = false
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                // No custom color: the menu bar's own text color stays legible on
                // any wallpaper.
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ])
            let task = (tracker.running ?? paused).map { tracker.task(for: $0) }
            button.toolTip = task.map { "\($0.task.name) · \($0.subtitle)" } ?? "Harvestbeam (⌥H)"
            button.layoutSubtreeIfNeeded()
            if let cell = button.cell as? NSButtonCell {
                controlButton.frame = cell.imageRect(forBounds: button.bounds)
            }
        } else {
            controlButton.isHidden = true
            let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Harvestbeam")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Harvestbeam (⌥H)"
        }
    }
}

/// A utility window that can take keyboard focus for the search field.
final class TrackerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

