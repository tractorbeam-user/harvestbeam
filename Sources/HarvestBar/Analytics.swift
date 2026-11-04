import Foundation
import HarvestKit
import TelemetryDeck

/// Anonymous usage counts with TelemetryDeck: how many people use Harvestbeam,
/// on which versions, and whether they get as far as signing in and starting
/// a timer. TelemetryDeck hashes a random install ID and gets the app and
/// macOS version; nothing from Harvest (projects, clients, notes, times,
/// your account or token) is ever sent.
///
/// Off when the build has no TelemetryDeckAppID (local and `swift run`
/// builds), in demo mode, and when "Share anonymous usage stats" is off in
/// Preferences.
@MainActor
enum Analytics {
    nonisolated static let enabledKey = "prefs.shareUsage"

    private static var isRunning = false

    private static var appID: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String
        return id?.isEmpty == false ? id : nil
    }

    /// Whether this build can send anything at all, so Preferences only shows
    /// the switch when it does something.
    static var isAvailable: Bool { appID != nil }

    /// Call once at launch, and again whenever the switch changes.
    static func update(isDemo: Bool) {
        let wanted = appID != nil && !isDemo && UserDefaults.standard.bool(forKey: enabledKey)
        if wanted, !isRunning, let appID {
            // Starting up sends TelemetryDeck's own "session started" signal,
            // which is what counts active users.
            TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
            isRunning = true
        } else if !wanted, isRunning {
            TelemetryDeck.terminate()
            isRunning = false
        }
    }

    static func send(_ event: UsageEvent) {
        guard isRunning else { return }
        TelemetryDeck.signal(event.rawValue)
    }
}
