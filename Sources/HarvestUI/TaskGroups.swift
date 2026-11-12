import HarvestKit
import Observation
import SwiftUI

/// Your own named groups of tasks ("Active Projects"), shown as panels like
/// Favorites, above or below it. Saved locally.
@MainActor @Observable
public final class TaskGroups {
    public struct Group: Codable, Identifiable, Equatable {
        public var id: String
        var name: String
        var keys: [String]
        /// "group:<id>", the section id on screen.
        public var sectionID: String { TaskGroups.sectionPrefix + id }
    }

    public static let shared = TaskGroups()
    nonisolated static let sectionPrefix = "group:"
    nonisolated static let favoritesID = "favorites"
    private static let defaultsKey = "taskGroups.v1"

    private(set) var groups: [Group] = []
    /// Every section top to bottom, as you arranged them: Favorites, Recent,
    /// Suggested and your groups.
    private var arrangement: [String] = []
    /// Sections shown at half width; two in a row sit side by side.
    private(set) var halfWidth: Set<String> = ["recent", "suggested"]
    /// Each section's look (Tiles, Launcher Grid, Rows), by section id.
    private var styles: [String: String] = [:]

    func style(for id: String) -> FavoritesStyle {
        styles[id].flatMap(FavoritesStyle.init) ?? .classic
    }

    func setStyle(_ style: FavoritesStyle, for id: String) {
        styles[id] = style.rawValue
        save()
    }

    /// The group whose name is being typed, right after New Group or Rename.
    public var renaming: String?

    /// Your own groups are switched off for now: none show, and nothing
    /// offers to make one. What's saved stays saved.
    nonisolated static let customGroupsEnabled = false

    /// How many tiles across a full-width section shows: 2 or 3.
    private var columnCounts: [String: Int] = [:]

    func columns(for id: String) -> Int { columnCounts[id] ?? 2 }

    func setColumns(_ count: Int, for id: String) {
        columnCounts[id] = count
        save()
    }

    nonisolated static let builtIn = ["favorites", "recent", "suggested"]

    private struct Saved: Codable {
        var groups: [Group]
        var favoritesIndex: Int?
        var arrangement: [String]?
        var halfWidth: [String]?
        var styles: [String: String]?
        var columns: [String: Int]?
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            groups = saved.groups
            if let arrangement = saved.arrangement {
                self.arrangement = arrangement
            } else {
                var ids = groups.map(\.sectionID)
                ids.insert(Self.favoritesID, at: min(max(saved.favoritesIndex ?? 0, 0), ids.count))
                self.arrangement = ids + ["recent", "suggested"]
            }
            if let half = saved.halfWidth { halfWidth = Set(half) }
            styles = saved.styles ?? [:]
            columnCounts = saved.columns ?? [:]
        }
    }

    /// Section ids top to bottom. Anything not placed yet (a new group)
    /// comes just after Favorites; Recent and Suggested default to the end.
    public var order: [String] {
        let valid = Self.builtIn + (Self.customGroupsEnabled ? groups.map(\.sectionID) : [])
        var ids = arrangement.filter(valid.contains)
        for id in valid where !ids.contains(id) {
            if id.hasPrefix(Self.sectionPrefix), let at = ids.firstIndex(of: Self.favoritesID) {
                ids.insert(id, at: at + 1)
            } else {
                ids.append(id)
            }
        }
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

    /// Puts a section just before another (or last).
    public func placeSection(_ id: String, before target: String?) {
        guard id != target else { return }
        var ids = order
        guard let from = ids.firstIndex(of: id) else { return }
        let targetIndex = target.flatMap { ids.firstIndex(of: $0) }
        ids.remove(at: from)
        if let target, let at = ids.firstIndex(of: target) {
            let movesLater = targetIndex.map { from < $0 } ?? false
            ids.insert(id, at: movesLater ? at + 1 : at)
        } else {
            ids.append(id)
        }
        arrangement = ids
        save()
    }

    func group(forSection id: String) -> Group? {
        guard id.hasPrefix(Self.sectionPrefix) else { return nil }
        let groupID = String(id.dropFirst(Self.sectionPrefix.count))
        return groups.first { $0.id == groupID }
    }

    /// A new, empty group just below Favorites, its name ready to type.
    @discardableResult
    public func create(named name: String = "New Group", with key: TaskKey? = nil) -> Group {
        let group = Group(id: UUID().uuidString, name: uniqueName(name), keys: key.map { [$0.description] } ?? [])
        var ids = order
        let at = (ids.firstIndex(of: Self.favoritesID) ?? -1) + 1
        groups.append(group)
        ids.insert(group.sectionID, at: at)
        arrangement = ids
        renaming = group.id
        save()
        return group
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        if !trimmed.isEmpty, trimmed != groups[index].name { groups[index].name = uniqueName(trimmed, except: id) }
        save()
    }

    public func delete(_ id: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        arrangement.removeAll { $0 == groups[index].sectionID }
        halfWidth.remove(groups[index].sectionID)
        groups.remove(at: index)
        if renaming == id { renaming = nil }
        save()
    }

    func contains(_ key: TaskKey, in id: String) -> Bool {
        groups.first { $0.id == id }?.keys.contains(key.description) ?? false
    }

    public func toggle(_ key: TaskKey, in id: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        if let at = groups[index].keys.firstIndex(of: key.description) {
            groups[index].keys.remove(at: at)
        } else {
            groups[index].keys.append(key.description)
        }
        save()
    }

    /// Puts `key` just before `target` in a group (or at the end), adding it
    /// if it isn't there yet. Moving later lands just after the target, so a
    /// tile can move one step either way.
    func place(_ key: TaskKey, before target: TaskKey?, in id: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }), key != target else { return }
        var keys = groups[index].keys
        let from = keys.firstIndex(of: key.description)
        let targetIndex = target.flatMap { keys.firstIndex(of: $0.description) }
        keys.removeAll { $0 == key.description }
        if let target, let at = keys.firstIndex(of: target.description) {
            let movesLater = from != nil && targetIndex != nil && from! < targetIndex!
            keys.insert(key.description, at: movesLater ? at + 1 : at)
        } else {
            keys.append(key.description)
        }
        groups[index].keys = keys
        save()
    }

    /// Whether a section can move up (-1) or down (+1).
    func canMove(_ sectionID: String, by offset: Int) -> Bool {
        guard let at = order.firstIndex(of: sectionID) else { return false }
        return order.indices.contains(at + offset)
    }

    /// Moves a group, or Favorites, one place up (-1) or down (+1).
    public func move(_ sectionID: String, by offset: Int) {
        var ids = order
        guard let at = ids.firstIndex(of: sectionID), ids.indices.contains(at + offset) else { return }
        ids.swapAt(at, at + offset)
        arrangement = ids
        save()
    }

    private func uniqueName(_ name: String, except id: String? = nil) -> String {
        let taken = Set(groups.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)".lowercased()) { n += 1 }
        return "\(name) \(n)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(groups: groups, arrangement: order, halfWidth: halfWidth.sorted(), styles: styles, columns: columnCounts)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
