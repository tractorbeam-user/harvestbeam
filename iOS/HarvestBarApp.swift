import HarvestKit
import HarvestUI
import SwiftUI

/// iPhone and iPad app. Same tracker, favorites and lists as the Mac menu bar
/// app, laid out as a native list with pull-to-refresh and swipe-to-favorite.
@main
struct HarvestBarApp: App {
    @State private var tracker = ProcessInfo.processInfo.arguments.contains("--demo") ? TimeTracker.demo() : TimeTracker.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tracker)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { tracker.didAppear() }
                }
        }
    }
}
