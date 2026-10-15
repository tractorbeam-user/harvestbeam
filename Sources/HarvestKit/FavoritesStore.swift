import Foundation
import Observation

/// Starred tasks, in the order the user starred them, optionally filed into
/// folders.
///
/// Saved locally and, when the app is signed with an iCloud entitlement,
/// mirrored to iCloud key-value storage so favorites and folders follow you
/// between Mac, iPhone and iPad.
@MainActor @Observable
public final class FavoritesStore {
    public private(set) var keys: [TaskKey] = []
    public private(set) var folders: [String] = []
    public private(set) var folderOf: [TaskKey: String] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    private static let keysKey = "favorites.v1"
    private static let foldersKey = "favoriteFolders.v1"
    private static let folderMapKey = "favoriteFolderMap.v1"

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
            folderOf[key] = nil
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

    // MARK: Folders

    public func keys(inFolder folder: String) -> [TaskKey] {
        keys.filter { folderOf[$0] == folder }
    }

    /// Adds a folder, making the name unique ("Clients 2"), and returns it.
    @discardableResult
    public func createFolder(named proposed: String = "New Folder") -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Folder" : proposed
        var name = base
        var n = 2
        while folders.contains(name) { name = "\(base) \(n)"; n += 1 }
        folders.append(name)
        persist()
        return name
    }

    public func renameFolder(_ folder: String, to proposed: String) {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = folders.firstIndex(of: folder), !name.isEmpty, name != folder, !folders.contains(name) else { return }
        folders[index] = name
        for (key, value) in folderOf where value == folder { folderOf[key] = name }
        persist()
    }

    /// Deletes the folder; its tasks stay favorites, just unfiled.
    public func deleteFolder(_ folder: String) {
        folders.removeAll { $0 == folder }
        folderOf = folderOf.filter { $0.value != folder }
        persist()
    }

    /// Files a task into a folder (starring it if needed), or unfiles it with nil.
    public func file(_ key: TaskKey, in folder: String?) {
        if !keys.contains(key) { keys.append(key) }
        folderOf[key] = folder.flatMap { folders.contains($0) ? $0 : nil }
        persist()
    }

    // MARK: Storage

    private func persist() {
        let raw = keys.map(\.description)
        let map = Dictionary(uniqueKeysWithValues: folderOf.map { ($0.key.description, $0.value) })
        defaults.set(raw, forKey: Self.keysKey)
        defaults.set(folders, forKey: Self.foldersKey)
        defaults.set(map, forKey: Self.folderMapKey)
        cloud?.set(raw, forKey: Self.keysKey)
        cloud?.set(folders, forKey: Self.foldersKey)
        cloud?.set(map, forKey: Self.folderMapKey)
    }

    private func load(preferCloud: Bool) {
        func array(_ key: String) -> [Any]? { (preferCloud ? cloud?.array(forKey: key) : nil) ?? defaults.array(forKey: key) }
        func dict(_ key: String) -> [String: Any]? { (preferCloud ? cloud?.dictionary(forKey: key) : nil) ?? defaults.dictionary(forKey: key) }
        keys = (array(Self.keysKey) as? [String] ?? []).compactMap(TaskKey.init)
        folders = array(Self.foldersKey) as? [String] ?? []
        var map: [TaskKey: String] = [:]
        for (raw, value) in dict(Self.folderMapKey) as? [String: String] ?? [:] {
            if let key = TaskKey(raw), folders.contains(value) { map[key] = value }
        }
        folderOf = map
    }
}
