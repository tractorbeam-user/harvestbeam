import AppKit
import HarvestUI
import SwiftUI

// The building blocks of the Preferences window, in the style of modern Mac
// settings apps: a full-height sidebar of panes, a header with back and
// forward, and grouped cards of rows with the control on the right.

/// One pane in the sidebar.
enum PrefsPane: String, CaseIterable, Identifiable {
    case general, tracking, shortcuts, support

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .tracking: "Tracking"
        case .shortcuts: "Shortcuts"
        case .support: "Support"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tracking: "wand.and.stars"
        case .shortcuts: "command"
        case .support: "wrench.adjustable"
        }
    }
}

// MARK: Colors

enum SettingsStyle {
    static let sidebar = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.135, alpha: 1))
    static let content = dynamic(light: .white, dark: NSColor(white: 0.17, alpha: 1))
    static let card = dynamic(light: NSColor(white: 0.957, alpha: 1), dark: NSColor(white: 0.215, alpha: 1))
    static let hairline = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))
    static let hover = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.06))
    static let keycap = dynamic(light: .white, dark: NSColor(white: 0.3, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: Window

/// Back and forward through the panes you've visited, like a browser.
private struct PaneHistory {
    var stack: [PrefsPane]
    var index = 0
    var current: PrefsPane { stack[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < stack.count - 1 }

    mutating func go(to pane: PrefsPane) {
        guard pane != current else { return }
        stack = Array(stack[...index]) + [pane]
        index += 1
    }
}

/// Sidebar on the left, the chosen pane on the right. The window's traffic
/// lights sit over the top of the sidebar.
struct SettingsWindow<Content: View>: View {
    let panes: [PrefsPane]
    @ViewBuilder var content: (PrefsPane) -> Content
    @State private var history: PaneHistory

    init(panes: [PrefsPane], initial: PrefsPane = .general, @ViewBuilder content: @escaping (PrefsPane) -> Content) {
        self.panes = panes
        self.content = content
        _history = State(initialValue: PaneHistory(stack: [initial]))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SettingsStyle.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    content(history.current)
                        .padding(.horizontal, 28)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(history.current)
            }
            .background(SettingsStyle.content)
        }
        .ignoresSafeArea()
        .tint(.harvestOrange)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(panes) { pane in
                SidebarRow(pane: pane, isSelected: pane == history.current) { history.go(to: pane) }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 52)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(SettingsStyle.sidebar)
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                chevron("chevron.left", help: "Back", enabled: history.canGoBack) { history.index -= 1 }
                Rectangle().fill(SettingsStyle.hairline).frame(width: 1, height: 14)
                chevron("chevron.right", help: "Forward", enabled: history.canGoForward) { history.index += 1 }
            }
            .background(Capsule().fill(SettingsStyle.card))
            .overlay(Capsule().strokeBorder(SettingsStyle.hairline))
            Text(history.current.title)
                .font(.system(size: 20, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func chevron(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!enabled)
        .help(help)
    }
}

private struct SidebarRow: View {
    let pane: PrefsPane
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.harvestOrange : (isHovered ? SettingsStyle.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: Sections and rows

/// A bold title above a rounded card of rows. Put a `CardDivider` between rows.
struct SettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 13, weight: .bold)).padding(.leading, 2)
            }
            SettingsCard { content }
            if let footer {
                Text(footer).settingsNote().padding(.horizontal, 2)
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SettingsStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SettingsStyle.hairline))
    }
}

/// The hairline between two rows in a card.
struct CardDivider: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.hairline).frame(height: 1).padding(.leading, 12)
    }
}

/// A small white symbol on a colored rounded square, leading a row.
struct RowIcon: View {
    let symbol: String
    let color: Color
    init(_ symbol: String, _ color: Color) {
        self.symbol = symbol
        self.color = color
    }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
    }
}

/// A label (and optional icon and description) on the left, a control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var description: String?
    var icon: RowIcon?
    @ViewBuilder var control: Control
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, description: String? = nil, icon: RowIcon? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.icon = icon
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon { icon.opacity(isEnabled ? 1 : 0.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let description {
                    Text(description).settingsNote()
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 42)
    }
}

extension SettingsRow where Control == SettingsSwitch {
    /// A row with a switch on the right.
    init(_ title: String, description: String? = nil, icon: RowIcon? = nil, isOn: Binding<Bool>) {
        self.init(title, description: description, icon: icon) { SettingsSwitch(isOn: isOn) }
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// The current value and ⌃⌄; click for a menu of choices.
struct SettingsPopup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .tint(.secondary)
        .fixedSize()
    }
}

extension SettingsPopup where Value == Int {
    /// Whole-number choices, keeping the current value even if it isn't one of them.
    init(selection: Binding<Int>, choices: [Int], label: @escaping (Int) -> String) {
        self.init(selection: selection, options: Array(Set(choices + [selection.wrappedValue])).sorted(), label: label)
    }
}

/// A key combo like ⌥⌘N drawn as keycaps.
struct Keycaps: View {
    let combo: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(combo.split(separator: " ").enumerated()), id: \.offset) { _, group in
                HStack(spacing: 3) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, key in
                        Text(String(key))
                            .font(.system(size: 11, weight: .medium))
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, key.isLetter && String(key).count > 1 ? 4 : 0)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(SettingsStyle.keycap))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(SettingsStyle.hairline))
                            .shadow(color: .black.opacity(0.06), radius: 0, y: 1)
                    }
                }
            }
        }
    }
}

extension View {
    func settingsNote() -> some View {
        font(.system(size: 11.5)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
