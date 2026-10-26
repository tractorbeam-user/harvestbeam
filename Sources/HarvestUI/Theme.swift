import SwiftUI
#if os(macOS)
import AppKit
#endif

public extension ShapeStyle where Self == Color {
    /// Harvest's brand orange, #FA5D00.
    static var harvestOrange: Color { Color(red: 250 / 255, green: 93 / 255, blue: 0) }
}

extension Color {
    /// Opaque window background; tiles sit on top of it. On the Mac it's a
    /// barely-there warm grey, so white cards lift off it (warm near-black in
    /// dark mode).
    static var panelBackground: Color {
        #if os(macOS)
        .adaptive(light: 0xF8F7F5, dark: 0x1F1B18)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Opaque tile and card fill: white in light mode, one warm step up in
    /// dark mode.
    static var tileBackground: Color {
        #if os(macOS)
        .adaptive(light: 0xFFFFFF, dark: 0x29241F)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// The 1pt line around tiles, cards and the search box.
    static var hairline: Color {
        #if os(macOS)
        .adaptive(light: 0x1C1916, dark: 0xEEE9E4, alpha: 0.09)
        #else
        Color.primary.opacity(0.08)
        #endif
    }

    /// Pale orange behind Favorites, the running entry and soft buttons.
    static var orangeSoft: Color {
        #if os(macOS)
        .adaptive(light: 0xFA5D00, dark: 0xFF6614, alpha: 0.1, darkAlpha: 0.14)
        #else
        Color.harvestOrange.opacity(0.1)
        #endif
    }

    /// Calendar meetings not logged yet: a pale blue, like a calendar event.
    static var meetingFill: Color {
        #if os(macOS)
        .adaptive(light: 0xDCEBFB, dark: 0x1D3550)
        #else
        Color.blue.opacity(0.15)
        #endif
    }

    static var meetingText: Color {
        #if os(macOS)
        .adaptive(light: 0x1F5FAD, dark: 0xA9CCF5)
        #else
        Color.blue
        #endif
    }

    #if os(macOS)
    static func adaptive(light: UInt32, dark: UInt32, alpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> Color {
        func color(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark, darkAlpha ?? alpha) : color(light, alpha)
        })
    }
    #endif
}

enum Metrics {
    #if os(macOS)
    static let tileMinWidth: CGFloat = 170
    static let tileHeight: CGFloat = 46
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 14
    static let badgeSize: CGFloat = 30
    #else
    static let tileMinWidth: CGFloat = 155
    static let tileHeight: CGFloat = 56
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let badgeSize: CGFloat = 34
    #endif
    static let tileCorner: CGFloat = 12
    static let cardCorner: CGFloat = 14
    /// Favorites' orange panel.
    static let panelCorner: CGFloat = 16
}

/// Round button with a glyph, used for Pause/Resume.
struct CircleButtonStyle: ButtonStyle {
    var size: CGFloat = 52
    var fill: Color = .harvestOrange
    var glyph: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// What the host window can do, so the shared UI can offer it. The Mac app
/// provides this; iOS leaves it nil.
public struct WindowActions: Sendable {
    public var close: @MainActor @Sendable () -> Void
    public var snapToMenuBar: @MainActor @Sendable () -> Void
    public var resetSize: @MainActor @Sendable () -> Void
    public var isKeptOnTop: @MainActor @Sendable () -> Bool
    public var setKeptOnTop: @MainActor @Sendable (Bool) -> Void
    public var setTitle: @MainActor @Sendable (String) -> Void
    /// Opens the Preferences window; set by the Mac app after init.
    public var openPreferences: (@MainActor @Sendable () -> Void)?
    /// Opens the week calendar window; set by the Mac app after init.
    public var openWeekCalendar: (@MainActor @Sendable () -> Void)?

    public init(
        close: @escaping @MainActor @Sendable () -> Void,
        snapToMenuBar: @escaping @MainActor @Sendable () -> Void,
        resetSize: @escaping @MainActor @Sendable () -> Void,
        isKeptOnTop: @escaping @MainActor @Sendable () -> Bool,
        setKeptOnTop: @escaping @MainActor @Sendable (Bool) -> Void,
        setTitle: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.close = close
        self.snapToMenuBar = snapToMenuBar
        self.resetSize = resetSize
        self.isKeptOnTop = isKeptOnTop
        self.setKeptOnTop = setKeptOnTop
        self.setTitle = setTitle
    }
}

private struct WindowActionsKey: EnvironmentKey {
    static let defaultValue: WindowActions? = nil
}

public extension EnvironmentValues {
    var windowActions: WindowActions? {
        get { self[WindowActionsKey.self] }
        set { self[WindowActionsKey.self] = newValue }
    }
}

public extension Notification.Name {
    /// The Mac window saw a click in a text field (its ask box), which opens
    /// Recent and Suggested.
    static let askFieldClicked = Notification.Name("HarvestUI.askFieldClicked")
}

/// Counts open popovers so the window behind them can dim, like Harvest's.
@MainActor @Observable
final class PopoverDimmer {
    var openCount = 0
}

private struct DimsWindow: ViewModifier {
    @Environment(PopoverDimmer.self) private var dimmer: PopoverDimmer?
    @State private var counted = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !counted else { return }
                counted = true
                dimmer?.openCount += 1
            }
            // Lift the dim as soon as the popover starts closing, not after
            // its close animation finishes.
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSPopover.willCloseNotification)) { _ in undim() }
            #endif
            .onDisappear { undim() }
    }

    private func undim() {
        guard counted else { return }
        counted = false
        dimmer.map { $0.openCount = max(0, $0.openCount - 1) }
    }
}

extension View {
    /// Put on a popover's content to dim the window while it's open.
    func dimsWindow() -> some View { modifier(DimsWindow()) }
}
