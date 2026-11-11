import AppKit
import HarvestKit
import HarvestUI
import SwiftUI

/// The Weekly Summary in a window of its own, remembered where you leave it.
@MainActor
final class WeeklySummaryWindowController: NSWindowController {
    private static let frameName = "HarvestbeamWeeklySummary"
    private let navigator = WeeklySummaryNavigator()
    private let tracker: TimeTracker

    init(tracker: TimeTracker) {
        self.tracker = tracker
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Weekly Summary"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 420)
        window.contentView = NSHostingView(rootView: WeeklySummaryView(navigator: navigator).environment(tracker))
        super.init(window: window)
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
    }

    required init?(coder: NSCoder) { nil }

    /// Shows the week holding `day`, or the default week (last week on a
    /// Monday, otherwise this one).
    func show(day: LocalDate?) {
        navigator.weekStart = day.map { $0.startOfWeek(firstWeekday: tracker.firstWeekday) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
