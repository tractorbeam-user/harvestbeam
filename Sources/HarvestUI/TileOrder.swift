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

    /// Moves `key` just before `target`, starting from the order on screen.
    func place(_ key: TaskKey, before target: TaskKey, in section: String, current: [TaskKey]) {
        var list = current.map(\.description).filter { $0 != key.description }
        let index = list.firstIndex(of: target.description) ?? list.endIndex
        list.insert(key.description, at: index)
        orders[section] = list
        UserDefaults.standard.set(orders, forKey: Self.defaultsKey)
    }
}
