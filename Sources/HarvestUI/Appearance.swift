import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Light, Dark, or follow the system (the default), picked in the window's
/// ⋯ menu or Preferences.
public enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    public static let key = "appearance"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// Saves the choice and applies it to every window right away.
    @MainActor public static func set(_ appearance: AppAppearance) {
        UserDefaults.standard.set(appearance.rawValue, forKey: key)
        apply()
    }

    /// Applies the saved choice; call at launch.
    @MainActor public static func apply() {
        #if os(macOS)
        switch current {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }
}
