import Foundation

/// Beta features: the Toggl-style automatic tracking (Timeline, on-screen
/// suggestions, Autotracker rules, auto-logged meetings, the Continue/Stop
/// shortcut). On in beta builds (`scripts/build-app.sh` with CHANNEL=beta),
/// with `--beta` on a debug run, or in the regular app when Preferences ›
/// Labs turns them on. Read once at launch, so turning Labs on or off takes
/// a relaunch.
public enum Beta {
    /// The old single Labs switch; still turns automatic tracking on.
    public static let labsKey = "labs.betaFeatures"
    /// Labs › Automatic tracking: the Timeline, suggestions from the screen
    /// and Autotracker rules, which share the screen watcher. Read at launch.
    public static let automaticTrackingKey = "labs.automaticTracking"
    /// Labs › Continue shortcut. Read live.
    public static let continueShortcutKey = "labs.continueShortcut"

    /// The separate Harvestbeam Beta app, which also takes beta updates and
    /// has every beta feature on.
    public static let isBetaBuild: Bool =
        Bundle.main.object(forInfoDictionaryKey: "HBBetaFeatures") as? Bool == true

    /// Every beta feature on: the beta app, or a debug run with --beta.
    public static let isEnabled: Bool = isBetaBuild || CommandLine.arguments.contains("--beta")

    /// Whether the screen watcher runs this launch.
    public static let automaticTracking: Bool =
        isEnabled
        || UserDefaults.standard.bool(forKey: automaticTrackingKey)
        || UserDefaults.standard.bool(forKey: labsKey)

    public static var continueShortcut: Bool {
        isEnabled || UserDefaults.standard.bool(forKey: continueShortcutKey)
    }

    /// The Sparkle channel beta builds also take updates from.
    public static let channel = "beta"
}

/// The app's own name: "Harvestbeam", or "Harvestbeam Beta" for the beta.
public enum AppInfo {
    public static let name: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Harvestbeam"
}
