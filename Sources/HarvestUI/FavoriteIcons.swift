import HarvestKit
import Observation
import SwiftUI

/// An icon on a favorite, like a Notion page icon: an emoji, or an SF Symbol
/// in one of a few colors.
enum FavoriteIcon: Equatable {
    case emoji(String)
    case symbol(String, color: Int)

    /// Saved as "e:🎨" or "s:paintpalette:2".
    init?(_ raw: String) {
        if raw.hasPrefix("e:") {
            self = .emoji(String(raw.dropFirst(2)))
        } else if raw.hasPrefix("s:") {
            let parts = raw.dropFirst(2).split(separator: ":")
            guard let name = parts.first else { return nil }
            self = .symbol(String(name), color: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
        } else {
            return nil
        }
    }

    var raw: String {
        switch self {
        case .emoji(let e): return "e:" + e
        case .symbol(let name, let color): return "s:\(name):\(color)"
        }
    }

    static let colors: [Color] = [
        .harvestOrange,
        Color(red: 0.22, green: 0.54, blue: 0.87),
        Color(red: 0.11, green: 0.62, blue: 0.46),
        Color(red: 0.50, green: 0.47, blue: 0.87),
        Color(red: 0.83, green: 0.33, blue: 0.49),
        Color(red: 0.53, green: 0.53, blue: 0.50),
    ]

    static let emoji = [
        "🎨", "🖌️", "✏️", "📐", "🧪", "🗂️", "💼", "📊",
        "📅", "🗣️", "💡", "🚀", "🧾", "🤝", "📚", "☕️",
        "💻", "📱", "🛠️", "🔍", "📝", "📣", "🎯", "🧠",
        "📦", "🌐", "🎬", "📷", "🎵", "🏢", "✈️", "⭐️",
    ]

    static let symbols = [
        "paintpalette", "chevron.left.forwardslash.chevron.right", "person.2", "doc.text",
        "briefcase", "calendar", "book", "lightbulb",
        "paperplane", "chart.bar", "pencil", "envelope",
        "gearshape", "magnifyingglass", "flag", "cup.and.saucer",
        "hammer", "megaphone", "target", "brain",
        "shippingbox", "globe", "film", "camera",
        "music.note", "building.2", "airplane", "star",
        "dollarsign.circle", "checkmark.seal", "bubble.left.and.bubble.right", "sparkles",
    ]
}

/// Icons for favorites, keyed by task. Saved locally.
@MainActor @Observable
public final class FavoriteIcons {
    public static let shared = FavoriteIcons()
    private static let defaultsKey = "favoriteIcons.v1"
    private var raw: [String: String]

    private init() {
        raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// Rereads what's saved (the debug snapshots set icons directly).
    public func reload() {
        raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    func icon(for key: TaskKey) -> FavoriteIcon? {
        raw[key.description].flatMap(FavoriteIcon.init)
    }

    func set(_ icon: FavoriteIcon?, for key: TaskKey) {
        raw[key.description] = icon?.raw
        UserDefaults.standard.set(raw, forKey: Self.defaultsKey)
    }
}

/// Draws a favorite's icon. On the orange running tile, symbols turn white.
struct FavoriteIconView: View {
    let icon: FavoriteIcon
    var size: CGFloat = 15
    var onOrange = false

    var body: some View {
        switch icon {
        case .emoji(let e):
            Text(e).font(.system(size: size))
        case .symbol(let name, let color):
            let tint = FavoriteIcon.colors[min(max(color, 0), FavoriteIcon.colors.count - 1)]
            Image(systemName: name)
                .font(.system(size: size * 0.82, weight: .medium))
                .foregroundStyle(onOrange ? .white : tint)
                .frame(width: size * 1.45, height: size * 1.45)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
                        .fill(onOrange ? Color.white.opacity(0.2) : tint.opacity(0.14))
                )
        }
    }
}

/// The picker: Emoji or Symbols tabs, a color row for symbols, and Remove.
struct FavoriteIconPicker: View {
    let key: TaskKey
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var color = 0
    @State private var typed = ""
    private let icons = FavoriteIcons.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Emoji").tag(0)
                    Text("Symbols").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if icons.icon(for: key) != nil {
                    Button("Remove") { pick(nil) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            if tab == 0 {
                TextField("Type or paste any emoji", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: typed) {
                        if let first = typed.first(where: { $0.unicodeScalars.first?.properties.isEmojiPresentation == true || $0.unicodeScalars.count > 1 }) {
                            pick(.emoji(String(first)))
                        }
                    }
                grid(FavoriteIcon.emoji) { e in
                    Text(e).font(.system(size: 20))
                } action: { pick(.emoji($0)) }
            } else {
                HStack(spacing: 8) {
                    ForEach(FavoriteIcon.colors.indices, id: \.self) { index in
                        Circle()
                            .fill(FavoriteIcon.colors[index])
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.primary.opacity(color == index ? 0.5 : 0), lineWidth: 2).padding(-3))
                            .onTapGesture { color = index }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.leading, 3)
                grid(FavoriteIcon.symbols) { name in
                    Image(systemName: name)
                        .font(.system(size: 16))
                        .foregroundStyle(FavoriteIcon.colors[color])
                } action: { pick(.symbol($0, color: color)) }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            if case .symbol(_, let c) = icons.icon(for: key) { tab = 1; color = c }
        }
    }

    private func grid<Cell: View>(_ items: [String], @ViewBuilder cell: @escaping (String) -> Cell,
                                  action: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    cell(item).frame(width: 32, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(IconCellStyle())
            }
        }
    }

    private func pick(_ icon: FavoriteIcon?) {
        withAnimation(.snappy(duration: 0.2)) { icons.set(icon, for: key) }
        dismiss()
    }
}

private struct IconCellStyle: ButtonStyle {
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(configuration.isPressed ? 0.12 : isHovered ? 0.07 : 0)))
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
    }
}

/// Adds "Choose Icon…" and the picker popover to a favorite.
struct FavoriteIconPopover: ViewModifier {
    let key: TaskKey
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FavoriteIconPicker(key: key)
        }
    }
}
