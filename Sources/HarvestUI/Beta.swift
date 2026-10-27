import Foundation

/// Beta features: the Toggl-style automatic tracking (Timeline, on-screen
/// suggestions, Autotracker rules, auto-logged meetings, the Continue/Stop
/// shortcut). They're in every build but only switched on in beta builds,
/// which `scripts/build-app.sh` makes with CHANNEL=beta. `--beta` turns them
/// on for a debug run.
public enum Beta {
    public static let isEnabled: Bool =
        Bundle.main.object(forInfoDictionaryKey: "HBBetaFeatures") as? Bool == true
        || CommandLine.arguments.contains("--beta")

    /// The Sparkle channel beta builds also take updates from.
    public static let channel = "beta"
}

/// The app's own name: "Harvestbeam", or "Harvestbeam Beta" for the beta.
public enum AppInfo {
    public static let name: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Harvestbeam"
}
