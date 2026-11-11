import HarvestKit
import SwiftUI

// Locked entries and archived projects/tasks: a tag that says so, muted
// styling, and a popover that says why and what to do about it.

extension EntryLock {
    var icon: String {
        switch kind {
        case .invoiced: "doc.text.fill"
        case .approved: "checkmark.seal.fill"
        case .locked: "lock.fill"
        }
    }
}

extension Color {
    /// Locked entries' tag and accent: a quiet slate, so it reads as "settled",
    /// not as an error.
    static var lockedTint: Color {
        #if os(macOS)
        .adaptive(light: 0x4F5B6B, dark: 0xB4C0CF)
        #else
        Color(red: 0x4F / 255, green: 0x5B / 255, blue: 0x6B / 255)
        #endif
    }

    static var lockedFill: Color {
        #if os(macOS)
        .adaptive(light: 0x4F5B6B, dark: 0xB4C0CF, alpha: 0.12, darkAlpha: 0.16)
        #else
        Color(red: 0x4F / 255, green: 0x5B / 255, blue: 0x6B / 255).opacity(0.12)
        #endif
    }

    /// Archived work: the amber used for warnings elsewhere.
    static var archivedTint: Color { .shortDay }

    static var archivedFill: Color {
        #if os(macOS)
        .adaptive(light: 0xEF9F27, dark: 0xEF9F27, alpha: 0.18, darkAlpha: 0.18)
        #else
        Color(red: 0xEF / 255, green: 0x9F / 255, blue: 0x27 / 255).opacity(0.18)
        #endif
    }
}

/// A small capsule: "Invoiced #1042", "Approved", "Archived".
struct StatusTag: View {
    let text: String
    let systemImage: String
    let tint: Color
    let fill: Color

    static func lock(_ lock: EntryLock, invoice: String? = nil) -> StatusTag {
        StatusTag(text: invoice.map { "\(lock.title) #\($0)" } ?? lock.title, systemImage: lock.icon,
                  tint: .lockedTint, fill: .lockedFill)
    }

    static func archived(_ reason: TaskUnavailability) -> StatusTag {
        StatusTag(text: reason.title, systemImage: "archivebox.fill", tint: .archivedTint, fill: .archivedFill)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 8.5, weight: .bold))
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(Capsule().fill(fill))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Why an entry or task can't be changed or started: one section per reason,
/// then a link to Harvest and, for a favorite, a way to unstar it.
struct StatusExplanation: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    var lock: EntryLock?
    var archived: TaskUnavailability?
    /// The day to open in Harvest; nil leaves the link out.
    var day: LocalDate?
    /// Set for a favorite: offers to remove it.
    var favoriteKey: TaskKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lock {
                section(icon: lock.icon, tint: .lockedTint, title: "\(lock.title) · can't be edited", detail: lock.detail)
            }
            if let archived {
                section(icon: "archivebox.fill", tint: .archivedTint, title: "Archived · can't be started", detail: archived.detail)
            }
            HStack(spacing: 14) {
                if let day, let url = tracker.harvestURL(for: day) {
                    Button { openURL(url) } label: {
                        Label("View in Harvest", systemImage: "arrow.up.forward").labelStyle(TrailingIconLabelStyle())
                    }
                }
                if let favoriteKey, tracker.favorites.contains(favoriteKey) {
                    Button("Remove from Favorites") {
                        dismiss()
                        withAnimation(.snappy(duration: 0.2)) { tracker.favorites.toggle(favoriteKey) }
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.harvestOrange)
            .padding(.leading, 28)
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .dimsWindow()
        .presentationBackground(Color.tileBackground)
    }

    private func section(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .bold))
        }
    }
}

/// On a tile for a task Harvest no longer offers: dims it, puts an Archived
/// tag over its play button, says why on hover, and on click explains
/// (with a way to unstar it) instead of trying to start it.
struct UnavailableTaskModifier: ViewModifier {
    @Environment(TimeTracker.self) private var tracker
    let key: TaskKey
    var cornerRadius: CGFloat
    @State private var isExplaining = false

    func body(content: Content) -> some View {
        if let reason = tracker.unavailability(of: key) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .saturation(0)
                // Washes the tile out, fully at the trailing end so the play
                // button is gone and the tag sits on a clean background.
                .overlay(shape.fill(LinearGradient(
                    stops: [.init(color: Color.tileBackground.opacity(0.5), location: 0),
                            .init(color: Color.tileBackground.opacity(0.7), location: 0.6),
                            .init(color: Color.tileBackground, location: 0.8)],
                    startPoint: .leading, endPoint: .trailing)))
                .overlay(alignment: .trailing) {
                    StatusTag.archived(reason).padding(.trailing, 10)
                }
                .overlay {
                    // Takes the click before the tile's own start-on-tap.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isExplaining = true }
                }
                .help(reason.help)
                .accessibilityValue("Archived, can't be started")
                .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
                    StatusExplanation(archived: reason, favoriteKey: key)
                }
        } else {
            content
        }
    }
}

extension View {
    /// Shows the tile as archived when Harvest no longer offers `key`.
    func unavailableTask(_ key: TaskKey, cornerRadius: CGFloat = Metrics.tileCorner) -> some View {
        modifier(UnavailableTaskModifier(key: key, cornerRadius: cornerRadius))
    }
}
