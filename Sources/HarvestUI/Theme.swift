import SwiftUI

public extension ShapeStyle where Self == Color {
    /// Harvest's brand orange, #FA5D00.
    static var harvestOrange: Color { Color(red: 250 / 255, green: 93 / 255, blue: 0) }
}

extension Color {
    /// Opaque window background; tiles sit on top of it.
    static var panelBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Opaque tile and card fill, one step lighter (or darker) than the panel.
    static var tileBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
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
    static let tileCorner: CGFloat = 16
    static let cardCorner: CGFloat = 20
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
