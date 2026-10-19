import AppKit
import Observation
import Sparkle

/// In-app updates with Sparkle, from the appcast.xml on main (SUFeedURL in
/// the Info.plist written by scripts/build-app.sh). Sparkle checks once a day
/// in the background; the app menu and Preferences can check right away.
@MainActor @Observable
final class Updates: NSObject, NSMenuItemValidation, SPUStandardUserDriverDelegate {
    /// False while a check is already running.
    private(set) var canCheck = false
    var checksAutomatically = true {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        // `swift run` builds have no Info.plist, so no feed: leave Sparkle off
        // rather than have it complain that it can't start.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(checkForUpdates(_:)) ? canCheck : true
    }

    // MARK: SPUStandardUserDriverDelegate

    // A menu bar app has no window in front, so Sparkle's alert could open
    // behind other apps. Say we handle reminders, then bring the app forward
    // whenever Sparkle is about to show an update.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: true) }
    }
}
