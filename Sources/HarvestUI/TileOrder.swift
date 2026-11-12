import HarvestKit
import Observation
import SwiftUI

/// Your own order for Recent and Suggested, set by dragging one tile onto
/// another. Tasks you haven't placed (new ones) come first, in the app's
/// order; the ones you placed follow in yours. Saved locally.
@MainActor @Observable
final class TileOrder {
    static let shared = TileOrder()
    private static let defaultsKey = "tileOrder.v1"
    private var orders: [String: [String]]

    private init() {
        orders = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: [String]] ?? [:]
    }

    func arranged(_ tasks: [TrackableTask], in section: String) -> [TrackableTask] {
        guard let order = orders[section], !order.isEmpty else { return tasks }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let unplaced = tasks.filter { rank[$0.key.description] == nil }
        let placed = tasks.filter { rank[$0.key.description] != nil }
            .sorted { rank[$0.key.description]! < rank[$1.key.description]! }
        return unplaced + placed
    }

    /// Moves `key` onto `target`'s place, starting from the order on screen:
    /// just before it, or just after when moving later, as in Favorites, so
    /// a tile can move one step either way.
    func place(_ key: TaskKey, before target: TaskKey, in section: String, current: [TaskKey]) {
        let ids = current.map(\.description)
        let movesLater = (ids.firstIndex(of: key.description) ?? .max) < (ids.firstIndex(of: target.description) ?? .min)
        var list = ids.filter { $0 != key.description }
        let at = list.firstIndex(of: target.description).map { movesLater ? $0 + 1 : $0 } ?? list.endIndex
        list.insert(key.description, at: at)
        orders[section] = list
        UserDefaults.standard.set(orders, forKey: Self.defaultsKey)
    }
}
