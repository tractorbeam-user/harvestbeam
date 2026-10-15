import Foundation
import Observation

/// Starred tasks, in the order the user starred them.
///
/// Saved locally and, when the app is signed with an iCloud entitlement,
/// mirrored to iCloud key-value storage so favorites follow you
/// between Mac, iPhone and iPad.
@MainActor @Observable
public final class FavoritesStore {
    public private(set) var keys: [TaskKey] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    private static let keysKey = "favorites.v1"

    public init(defaults: UserDefaults = .standard, syncWithICloud: Bool = true) {
        self.defaults = defaults
        // Without the iCloud entitlement there's no identity token, and the KVS
        // silently stays local, so skip it entirely.
        let cloudAvailable = syncWithICloud && FileManager.default.ubiquityIdentityToken != nil
        self.cloud = cloudAvailable ? NSUbiquitousKeyValueStore.default : nil
        load(preferCloud: true)

        if let cloud {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloud,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.load(preferCloud: true) }
            }
            cloud.synchronize()
        }
    }

    public var set: Set<TaskKey> { Set(keys) }

    public func contains(_ key: TaskKey) -> Bool { keys.contains(key) }

    public func toggle(_ key: TaskKey) {
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
        } else {
            keys.append(key)
        }
        persist()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { keys[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.reversed() { keys.remove(at: index) }
        keys.insert(contentsOf: moving, at: insertAt)
        persist()
    }

    /// Moves a favorite one place earlier (-1) or later (+1).
    public func shift(_ key: TaskKey, by offset: Int) {
        guard let index = keys.firstIndex(of: key) else { return }
        let target = min(max(index + offset, 0), keys.count - 1)
        guard target != index else { return }
        keys.remove(at: index)
        keys.insert(key, at: target)
        persist()
    }

    // MARK: Storage

    private func persist() {
        let raw = keys.map(\.description)
        defaults.set(raw, forKey: Self.keysKey)
        cloud?.set(raw, forKey: Self.keysKey)
    }

    private func load(preferCloud: Bool) {
        func array(_ key: String) -> [Any]? { (preferCloud ? cloud?.array(forKey: key) : nil) ?? defaults.array(forKey: key) }
        keys = (array(Self.keysKey) as? [String] ?? []).compactMap(TaskKey.init)
    }
}
