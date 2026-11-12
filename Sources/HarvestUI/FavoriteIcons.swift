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
        // Added later; saved icons refer to colors by position, so new ones go last.
        Color(red: 0.89, green: 0.66, blue: 0.10),
        Color(red: 0.10, green: 0.63, blue: 0.70),
        Color(red: 0.36, green: 0.36, blue: 0.84),
        Color(red: 0.55, green: 0.38, blue: 0.24),
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
        "seal", "heart", "bolt", "flame",
        "leaf", "paintbrush.pointed", "pencil.and.ruler", "square.on.square",
        "photo", "video", "mic", "headphones",
        "phone", "person.crop.circle", "person.3", "hand.raised",
        "folder", "tray.full", "archivebox", "doc.on.doc",
        "list.bullet.clipboard", "checklist", "chart.pie", "chart.line.uptrend.xyaxis",
        "cart", "creditcard", "banknote", "tag",
        "house", "storefront", "map", "mappin.and.ellipse",
        "car", "tram", "bicycle", "graduationcap",
        "laptopcomputer", "desktopcomputer", "iphone", "server.rack",
        "terminal", "curlybraces", "ant", "wrench.and.screwdriver",
        "cube", "puzzlepiece", "gift", "trophy",
        "clock", "hourglass", "bell", "sun.max",
        "moon", "cloud", "drop", "globe.americas",
    ]
}

/// Icons for favorites, keyed by task. Saved locally.
@MainActor @Observable
public final class FavoriteIcons {
    public static let shared = FavoriteIcons()
    private static let defaultsKey = "favoriteIcons.v1"
    private var raw: [String: String]
    /// Shown until you choose one: an outlined star.
    static let defaultIcon = FavoriteIcon.symbol("star", color: 0)

    private init() {
        raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// Rereads what's saved (the debug snapshots set icons directly).
    public func reload() {
        raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// The chosen icon, or the outlined star.
    func shownIcon(for key: TaskKey) -> FavoriteIcon { icon(for: key) ?? Self.defaultIcon }

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
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private let icons = FavoriteIcons.shared

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    /// The curated set until you type, then every match on this Mac.
    private var symbolResults: [String] { trimmed.isEmpty ? FavoriteIcon.symbols : SymbolCatalog.search(trimmed) }
    /// Emoji typed or pasted into the box come first, then matches by name.
    private var emojiResults: [String] {
        guard !trimmed.isEmpty else { return FavoriteIcon.emoji + EmojiCatalog.all.map(\.character).filter { !FavoriteIcon.emoji.contains($0) } }
        let pasted = trimmed.filter { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } || $0.unicodeScalars.count > 1 }.map(String.init)
        return pasted + EmojiCatalog.search(trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Symbols").tag(0)
                    Text("Emoji").tag(1)
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
            TextField(tab == 0 ? "Search all symbols" : "Search or paste emoji", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            if tab == 0 {
                HStack(spacing: 7) {
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
            }
            let results = Self.unique(tab == 0 ? symbolResults : emojiResults)
            ScrollView {
                if results.isEmpty {
                    Text("Nothing matches “\(trimmed)”")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                } else if tab == 0 {
                    grid(results) { name in
                        Image(systemName: name)
                            .font(.system(size: 16))
                            .foregroundStyle(FavoriteIcon.colors[color])
                    } action: { pick(.symbol($0, color: color)) }
                } else {
                    grid(results) { e in
                        Text(e).font(.system(size: 20))
                    } action: { pick(.emoji($0)) }
                }
            }
            .frame(height: 236)
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            searchFocused = true
            switch icons.icon(for: key) {
            case .emoji: tab = 1
            case .symbol(_, let c): color = c
            case nil: break
            }
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

    /// Each once, in order: the grid can't show the same item twice.
    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
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

#if DEBUG
/// The icon picker, for the debug snapshots.
@MainActor public func debugFavoriteIconPicker(_ key: TaskKey) -> some View { FavoriteIconPicker(key: key) }
#endif
