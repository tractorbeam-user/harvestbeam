import AppKit
import HarvestKit
import HarvestUI
import SwiftUI

/// The week calendar in a window of its own: wide enough for seven columns,
/// remembered where you leave it.
@MainActor
final class WeekCalendarWindowController: NSWindowController {
    private static let frameName = "HarvestbeamWeekCalendar"

    init(tracker: TimeTracker, calendar: CalendarStore, recorder: ActivityRecorder?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Week Calendar"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.contentView = NSHostingView(rootView: WeekCalendarView(calendar: calendar).environment(tracker).environment(recorder))
        super.init(window: window)
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
