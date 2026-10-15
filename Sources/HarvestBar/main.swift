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
    #endif
    let arguments = ProcessInfo.processInfo
    let demo = arguments.arguments.contains("--demo") || arguments.environment["HARVESTBAR_DEMO"] == "1"
    let delegate = AppDelegate(tracker: demo ? .demo() : .live())
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
