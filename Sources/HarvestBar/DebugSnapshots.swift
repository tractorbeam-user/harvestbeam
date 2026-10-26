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


            let entryWindow = makeWindow(debugNewEntryEditor().environment(tracker).frame(width: 340, height: 260), appearance: appearance)
            entryWindow.setContentSize(NSSize(width: 340, height: 260))
            await settle()
            write(entryWindow, to: url.appendingPathComponent("6-new-entry-\(suffix).png"))
            entryWindow.close()

            let today = LocalDate()
            let locksWindow = makeWindow(debugShortDayAndLocks(today: today.adding(days: -3), lockedDay: today.adding(days: -10))
                .environment(tracker).frame(width: 440, height: 680, alignment: .top), appearance: appearance)
            await settle()
            write(locksWindow, to: url.appendingPathComponent("5-short-day-locks-\(suffix).png"))
            locksWindow.close()

            let summaryWindow = makeWindow(debugTimeSummary().environment(tracker).frame(width: 300, height: 200), appearance: appearance)
            summaryWindow.setContentSize(NSSize(width: 300, height: 200))
            await settle()
            write(summaryWindow, to: url.appendingPathComponent("7-summary-\(suffix).png"))
            summaryWindow.close()

            let weekWindow = makeWindow(debugWeekCalendar().environment(tracker).frame(width: 1100, height: 760), appearance: appearance)
            weekWindow.setContentSize(NSSize(width: 1100, height: 760))
            await settle()
            write(weekWindow, to: url.appendingPathComponent("9-week-calendar-\(suffix).png"))
            weekWindow.close()

            let timelineWindow = makeWindow(debugWeekCalendarWithTimeline(tracker).environment(tracker).frame(width: 1300, height: 760), appearance: appearance)
            timelineWindow.setContentSize(NSSize(width: 1300, height: 760))
            await settle()
            write(timelineWindow, to: url.appendingPathComponent("9-week-timeline-\(suffix).png"))
            timelineWindow.close()
            UserDefaults.standard.removeObject(forKey: "weekCalendar.showsTimeline")

            let meetingWindow = makeWindow(debugMeetingEditor().environment(tracker).frame(width: 340, height: 300), appearance: appearance)
            meetingWindow.setContentSize(NSSize(width: 340, height: 300))
            await settle()
            write(meetingWindow, to: url.appendingPathComponent("9-log-meeting-\(suffix).png"))
            meetingWindow.close()

            for (name, view) in [("general", AnyView(GeneralPrefs())), ("shortcuts", AnyView(ShortcutPrefs())),
                                 ("tracking", AnyView(TrackingPrefs())), ("support", AnyView(SupportPrefs(resetLayout: {})))] {
                let prefsWindow = makeWindow(view.environment(tracker).environment(Updates()).environment(ActivityRecorder(tracker: tracker))
                    .frame(width: 480, height: name == "tracking" ? 1000 : 560, alignment: .top), appearance: appearance)
                prefsWindow.setContentSize(NSSize(width: 480, height: name == "tracking" ? 1000 : 560))
                await settle()
                write(prefsWindow, to: url.appendingPathComponent("8-prefs-\(name)-\(suffix).png"))
                prefsWindow.close()
            }

            for step in OnboardingModel.Step.allCases {
                let model = OnboardingModel(tracker: TimeTracker(service: nil, accountName: nil, favorites: tracker.favorites),
                                            shortcut: "⌥H", needsAccessibility: false)
                model.step = step
                let size = OnboardingView.size
                let welcome = makeWindow(OnboardingView().environment(model), appearance: appearance)
                welcome.setContentSize(size)
                await settle()
                write(welcome, to: url.appendingPathComponent("9-onboarding-\(step.rawValue)-\(suffix).png"))
                if step == .connect {
                    model.showsTokenHelp = true
                    await settle()
                    write(welcome, to: url.appendingPathComponent("9-onboarding-3-help-\(suffix).png"))
                }
                welcome.close()
            }

            if let field = firstTextField(in: window.contentView!) {
                window.makeFirstResponder(field)
                field.stringValue = "10 min on website"
                field.currentEditor()?.string = "10 min on website"
                NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
                (field.currentEditor() as? NSTextView)?.didChangeText()
            }
            await settle()
            write(window, to: url.appendingPathComponent("2-search-\(suffix).png"))

            await tracker.pause()
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
        await updateWindows(into: url)
    }

    /// The update window in each of its states.
    private static func updateWindows(into url: URL) async {
        if let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns") { NSApp.applicationIconImage = icon }
        let notes = UpdateDriver.markdownNotes(
            "**New:** pick up where you left off with Start Again Today.\n- The menu bar timer stays readable in dark mode.\n- Fixed a crash when a project had no tasks."
        )
        let info = UpdateInfo(version: "1.0.1", current: "0.9.0", notes: notes)
        let phases: [(String, UpdatePhase)] = [
            ("1-checking", .checking),
            ("2-found", .found(info)),
            ("3-found-no-notes", .found(UpdateInfo(version: "1.0.1", current: "0.9.0", notes: nil))),
            ("4-up-to-date", .upToDate("1.0.1")),
            ("5-downloading", .downloading(received: 1_300_000, expected: 3_431_507)),
            ("6-preparing", .preparing(0.6)),
            ("7-installing", .installing),
            ("8-ready", .ready(info)),
            ("9-error", .failed(UpdateFailure(whileChecking: true, detail: "The network connection was lost."))),
        ]
        let updates = Updates()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for (name, phase) in phases {
                let prompt = UpdatePrompt()
                prompt.version = "1.0.1"
                prompt.phase = phase
                let view = UpdateView().environment(prompt).environment(updates)
                let window = makeWindow(view, appearance: appearance)
                let size = window.contentView!.fittingSize
                window.setContentSize(size)
                await settle()
                write(window, to: url.appendingPathComponent("9-update-\(name)-\(suffix).png"))
                window.close()
            }
        }
    }

    private static func makeWindow(_ view: some View, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -3000, y: 0, width: 440, height: 680),
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
           ["", "Start something new…"].contains(field.placeholderString ?? field.placeholderAttributedString?.string ?? "") {
            return field
        }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }
}
#endif
