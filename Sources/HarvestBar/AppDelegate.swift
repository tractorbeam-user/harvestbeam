import AppKit
import HarvestKit
import HarvestUI
import SwiftUI

/// Owns the menu bar item and its popover. The item shows a clock when idle and
/// an orange dot with the elapsed time while a timer runs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let tracker: TimeTracker
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private var ticker: Timer?
    private var poller: Timer?
    private var lastTitle: String?

    init(tracker: TimeTracker) {
        self.tracker = tracker
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
            button.setAccessibilityTitle("Harvest Bar")
        }

        let host = NSHostingController(rootView: RootView { [weak self] in self?.closePopover() }.environment(tracker))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        hotKey = HotKey { [weak self] in self?.togglePopover() }
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
                guard let self, !self.popover.isShown else { return }
                Task { await self.tracker.refresh(force: true) }
            }
        }
        updateStatusItem()

        Task {
            await tracker.refresh(force: true)
            // First run: open the panel so there's somewhere to paste a token.
            if tracker.phase == .signedOut || tracker.isDemo { showPopover() }
        }
    }

    // MARK: Popover

    @objc func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        tracker.didAppear()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        tracker.errorMessage = nil
    }

    // MARK: Status item

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let title = tracker.running.map { " " + TimeFormat.hoursMinutes($0.elapsed()) } ?? ""
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
