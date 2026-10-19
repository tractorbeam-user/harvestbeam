import Foundation
import Testing
@testable import HarvestKit

@MainActor
struct FavoritesStoreTests {
    let a = TaskKey(projectID: 1, taskID: 1)
    let b = TaskKey(projectID: 2, taskID: 2)
    let c = TaskKey(projectID: 3, taskID: 3)

    func store() -> FavoritesStore {
        let defaults = UserDefaults(suiteName: "FavoritesStoreTests-\(UUID())")!
        let store = FavoritesStore(defaults: defaults, syncWithICloud: false)
        for key in [a, b, c] { store.toggle(key) }
        return store
    }

    @Test func droppingOnALaterTileMovesPastIt() {
        let favorites = store()
        favorites.place(a, before: b)
        #expect(favorites.keys == [b, a, c])
    }

    @Test func droppingOnAnEarlierTileMovesBeforeIt() {
        let favorites = store()
        favorites.place(c, before: b)
        #expect(favorites.keys == [a, c, b])
    }

    @Test func droppingOnThePanelMovesToTheEnd() {
        let favorites = store()
        favorites.place(a, before: nil)
        #expect(favorites.keys == [b, c, a])
    }
}
