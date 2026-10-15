import SwiftUI

public extension ShapeStyle where Self == Color {
    /// Harvest's brand orange, #FA5D00.
    static var harvestOrange: Color { Color(red: 250 / 255, green: 93 / 255, blue: 0) }
}

enum Metrics {
    #if os(macOS)
    static let rowHeight: CGFloat = 44
    static let badgeSize: CGFloat = 28
    static let actionSize: CGFloat = 28
    #else
    static let rowHeight: CGFloat = 56
    static let badgeSize: CGFloat = 34
    static let actionSize: CGFloat = 40
    #endif
}

/// Round orange button with a white glyph, used for Stop and in sign-in.
struct OrangeCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(.harvestOrange))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}
