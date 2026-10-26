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
    /// Continue the last entry, or stop the timer, from anywhere.
    private var continueHotKey: HotKey?
    private var reminders: Reminders?
    private let updates = Updates()
    private lazy var preferences = PreferencesWindowController(tracker: tracker, updates: updates, recorder: recorder) { [weak self] in
        self?.resetPanelSize()
    }
    private var ticker: Timer?
    private var poller: Timer?
    private var lastTitle: String?
    private var hasPlacedPanel = false
    private var onboarding: OnboardingWindowController?
    /// Made the first time it's opened.
    private var weekCalendar: WeekCalendarWindowController?
    /// Shared by the week calendar and the ask box's meeting suggestions.
    private lazy var calendarStore = tracker.isDemo ? CalendarStore.demo() : CalendarStore()
    /// What's in front: the Timeline, on-screen suggestions and the Autotracker.
    /// Beta builds only.
    private lazy var recorder: ActivityRecorder? = Beta.isEnabled ? ActivityRecorder(tracker: tracker) : nil
    private var autotracker: Autotracker?
    private var meetingLogger: MeetingAutoLogger?
    /// The app that was in front before the window opened.
    private var previousApp: NSRunningApplication?

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
        Notifier.registerCategories()
        if let recorder {
            let autotracker = Autotracker(tracker: tracker)
            self.autotracker = autotracker
            recorder.onTick = { [weak autotracker] context, dwell in autotracker?.tick(context, dwell: dwell) }
            meetingLogger = MeetingAutoLogger(tracker: tracker, calendar: calendarStore)
        }

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
            let forced = CommandLine.arguments.contains("--onboarding")
            if forced || (tracker.phase == .signedOut && !OnboardingWindowController.isCompleted) {
                showOnboarding()
            } else if tracker.phase == .signedOut || tracker.isDemo {
                // Open the window so there's somewhere to paste a token.
                showPanel()
            }
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
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(Updates.checkForUpdates(_:)), keyEquivalent: "").target = updates
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
        windowMenu.addItem(withTitle: "Week Calendar", action: #selector(showWeekCalendar), keyEquivalent: "k")
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
        // The same near-white (warm dark) surface the SwiftUI content paints, so
        // resizing never flashes the system grey.
        panel.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0x1F / 255, green: 0x1B / 255, blue: 0x18 / 255, alpha: 1)
                : NSColor(srgbRed: 0xF8 / 255, green: 0xF7 / 255, blue: 0xF5 / 255, alpha: 1)
        }
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
        windowActions.openWeekCalendar = { [weak self] in self?.showWeekCalendar() }
        let host = NSHostingView(rootView: RootView().environment(tracker).environment(calendarStore)
            .environment(recorder).environment(\.windowActions, windowActions))
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
            // Opened with the mouse, so don't grab the keyboard for the ask box.
            showPanel(focusSearch: false)
        }
    }

    /// The first-run welcome. When it's done, the tracker window takes over.
    private func showOnboarding() {
        let controller = OnboardingWindowController(
            tracker: tracker,
            shortcut: HotKey.Shortcut.load() == nil ? nil : UserDefaults.standard.string(forKey: Prefs.shortcutDisplay),
            needsAccessibility: hotKey?.mode == .needsAccessibility
        ) { [weak self] in
            self?.onboarding = nil
            self?.showPanel()
        }
        onboarding = controller
        controller.show()
    }

    /// ⌥H: bring the window forward, or hide it if it's already focused.
    @objc func togglePanel() {
        // During the welcome, the shortcut is something to try out.
        if let onboarding, onboarding.isVisible {
            onboarding.shortcutPressed()
            return
        }
        // In front with the window showing, even if a popover in it has focus:
        // put it away.
        if NSApp.isActive && panel.isVisible && !panel.isMiniaturized && panel.occlusionState.contains(.visible) {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel(focusSearch: Bool = true) {
        if !hasPlacedPanel {
            placeBelowStatusItem()
            hasPlacedPanel = true
        }
        // Remember where you were, to go straight back there on hide.
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApp = front
        }
        NSApp.unhide(nil)
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        // A menu bar app isn't the active app when you click its icon, and
        // macOS's polite activate() can leave the window behind others. Force
        // it to the front, above every other app's windows.
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        tracker.didAppear(focusSearch: focusSearch)
    }

    func hidePanel() {
        panel.orderOut(nil)
        tracker.errorMessage = nil
        // The week calendar stays up on its own; only the small window goes.
        if let week = weekCalendar?.window, week.isVisible, !week.isMiniaturized {
            previousApp = nil
            return
        }
        // Hand focus straight back to whatever you were working in.
        NSApp.hide(nil)
        if let app = previousApp, !app.isTerminated { app.activate() }
        previousApp = nil
    }

    static let defaultSize = NSSize(width: 440, height: 680)

    @objc func showPreferences() {
        preferences.show()
    }

    @objc func showWeekCalendar() {
        if weekCalendar == nil {
            weekCalendar = WeekCalendarWindowController(tracker: tracker, calendar: calendarStore, recorder: recorder)
        }
        weekCalendar?.show()
    }

    /// (Re)registers the show/hide shortcut from preferences; none if cleared.
    private func registerHotKey() {
        hotKey?.invalidate()
        hotKey = HotKey.Shortcut.load().map { shortcut in
            HotKey(id: 1, keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers) { [weak self] in self?.togglePanel() }
        }
        continueHotKey?.invalidate()
        continueHotKey = !Beta.isEnabled ? nil : HotKey.Shortcut.load("continue", default: nil).map { shortcut in
            HotKey(id: 2, keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers) { [weak self] in
                guard let self else { return }
                Task { await self.tracker.continueOrStop() }
            }
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
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let action = response.actionIdentifier
        let task = (content.userInfo["task"] as? String).flatMap(TaskKey.init)
        let entryID = (content.userInfo["entry"] as? String).flatMap(Int.init)
        await MainActor.run {
            switch category {
            case Notifier.autotrackCategory where action != UNNotificationDismissActionIdentifier:
                // Start, or a click on the notification itself.
                if let task { autotracker?.start(task) }
            case Notifier.autoLoggedCategory where action == Notifier.undoAction:
                if let entryID, let entry = tracker.entries.first(where: { $0.id == entryID }) {
                    Task { await tracker.deleteEntry(entry) }
                }
            default:
                showPanel()
            }
        }
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

    /// A click anywhere but a text field takes focus out of the field you were
    /// typing in, like clicking off a field on a web page. The click itself
    /// still goes through.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let hit = contentView?.hitTest(contentView!.convert(event.locationInWindow, from: nil)) {
            if Self.isInTextField(hit) {
                NotificationCenter.default.post(name: .askFieldClicked, object: nil)
            } else if firstResponder is NSText {
                makeFirstResponder(nil)
            }
        }
        super.sendEvent(event)
    }

    private static func isInTextField(_ view: NSView) -> Bool {
        sequence(first: view, next: \.superview).contains { $0 is NSTextField || $0 is NSTextView }
    }
}

