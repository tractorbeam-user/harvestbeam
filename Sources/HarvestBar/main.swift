import AppKit
import HarvestKit

// Menu bar only: no Dock icon, no main window.
MainActor.assumeIsolated {
    #if DEBUG
    if let index = CommandLine.arguments.firstIndex(of: "--snapshots"), CommandLine.arguments.count > index + 1 {
        let directory = CommandLine.arguments[index + 1]
        NSApplication.shared.setActivationPolicy(.accessory)
        Task {
            await DebugSnapshots.run(into: directory)
            exit(0)
        }
        NSApplication.shared.run()
    }
    // `HarvestBar --plan "text"` prints what the day planner proposes, using demo tasks.
    if let index = CommandLine.arguments.firstIndex(of: "--plan"), CommandLine.arguments.count > index + 1 {
        let text = CommandLine.arguments[index + 1]
        Task {
            let tracker = TimeTracker.demo()
            await tracker.refresh(force: true)
            print("model available:", DayPlanner.modelAvailable)
            let (entries, engine) = await tracker.planDay(text)
            print("engine:", engine)
            for e in entries {
                print("-", e.task.project.name, "·", e.task.task.name, "·", e.hours.map { String($0) } ?? "no hours", "·", e.notes)
            }
            exit(0)
        }
        NSApplication.shared.run()
    }
    #endif
    let arguments = ProcessInfo.processInfo
    let demo = arguments.arguments.contains("--demo") || arguments.environment["HARVESTBAR_DEMO"] == "1"
    let delegate = AppDelegate(tracker: demo ? .demo() : .live())
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    #if DEBUG
    // `--show` opens the window at launch, for testing.
    if arguments.arguments.contains("--show") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { delegate.showPanel() }
    }
    #endif
    app.run()
}
