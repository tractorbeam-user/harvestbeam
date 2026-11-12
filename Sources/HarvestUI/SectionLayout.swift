import Observation
import SwiftUI

/// How the task sections (Favorites, Recent, Suggested) are arranged: their
/// order top to bottom and which sit at half width. Saved on this Mac.
@MainActor @Observable
public final class SectionLayout {
    public static let shared = SectionLayout()
    nonisolated static let favoritesID = "favorites"
    nonisolated static let builtIn = ["favorites", "recent", "suggested"]
    /// Kept from when sections were called groups, so arrangements carry over.
    private static let defaultsKey = "taskGroups.v1"

    /// Every section top to bottom, as you arranged them.
    private var arrangement: [String] = []
    /// Sections shown at half width; two in a row sit side by side.
    private(set) var halfWidth: Set<String> = ["recent", "suggested"]

    private struct Saved: Codable {
        var arrangement: [String]?
        var halfWidth: [String]?
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            arrangement = saved.arrangement ?? []
            if let half = saved.halfWidth { halfWidth = Set(half) }
        }
    }

    /// Section ids top to bottom; any not placed yet go at the end.
    public var order: [String] {
        var ids = arrangement.filter(Self.builtIn.contains)
        for id in Self.builtIn where !ids.contains(id) { ids.append(id) }
        return ids
    }

    public func isHalf(_ id: String) -> Bool { halfWidth.contains(id) }

    public func toggleHalf(_ id: String) {
        if !halfWidth.insert(id).inserted { halfWidth.remove(id) }
        save()
    }

    /// Puts a section just before or after another, as dragging a title does.
    public func placeSection(_ id: String, nextTo target: String, after: Bool) {
        guard id != target else { return }
        var ids = order.filter { $0 != id }
        guard let at = ids.firstIndex(of: target) else { return }
        ids.insert(id, at: after ? at + 1 : at)
        arrangement = ids
        save()
    }

    /// Whether a section can move up (-1) or down (+1).
    func canMove(_ id: String, by offset: Int) -> Bool {
        guard let at = order.firstIndex(of: id) else { return false }
        return order.indices.contains(at + offset)
    }

    /// Moves a section one place up (-1) or down (+1).
    public func move(_ id: String, by offset: Int) {
        var ids = order
        guard let at = ids.firstIndex(of: id), ids.indices.contains(at + offset) else { return }
        ids.swapAt(at, at + offset)
        arrangement = ids
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(arrangement: order, halfWidth: halfWidth.sorted())) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
