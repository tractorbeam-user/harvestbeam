import AppKit
import Observation
import Sparkle

/// In-app updates with Sparkle, from the appcast.xml on main (SUFeedURL in
/// the Info.plist written by scripts/build-app.sh). Sparkle checks once a day
/// in the background; the app menu and Preferences can check right away.
/// Harvestbeam draws the update window itself (UpdateDriver).
@MainActor @Observable
final class Updates: NSObject, NSMenuItemValidation {
    /// False while a check is already running.
    private(set) var canCheck = false
    var checksAutomatically = true {
        didSet { updater?.automaticallyChecksForUpdates = checksAutomatically }
    }
    /// Download updates in the background and install them on quit, without asking.
    var installsAutomatically = false {
        didSet { updater?.automaticallyDownloadsUpdates = installsAutomatically }
    }

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var driver: UpdateDriver?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        // `swift run` builds have no Info.plist, so no feed: leave Sparkle off
        // rather than have it complain that it can't start.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let driver = UpdateDriver(updates: self)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        do {
            try updater.start()
        } catch {
            NSLog("Harvestbeam: Sparkle didn't start: \(error)")
            return
        }
        self.driver = driver
        self.updater = updater
        checksAutomatically = updater.automaticallyChecksForUpdates
        installsAutomatically = updater.automaticallyDownloadsUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater?.checkForUpdates()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(checkForUpdates(_:)) ? canCheck : true
    }
}
