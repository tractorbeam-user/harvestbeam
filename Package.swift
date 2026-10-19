// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HarvestBar",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "HarvestKit", targets: ["HarvestKit"]),
        .library(name: "HarvestUI", targets: ["HarvestUI"]),
        .executable(name: "HarvestBar", targets: ["HarvestBar"]),
    ],
    dependencies: [
        // In-app updates for the Mac app, from the appcast on main.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Models, Harvest API client, Keychain, ranking. No UI.
        .target(name: "HarvestKit"),
        // SwiftUI views shared by the Mac menu bar app and the iPhone/iPad app.
        .target(name: "HarvestUI", dependencies: ["HarvestKit"]),
        // The macOS menu bar shell: status item, popover, ⌥H shortcut.
        .executableTarget(
            name: "HarvestBar",
            dependencies: ["HarvestKit", "HarvestUI", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "HarvestKitTests", dependencies: ["HarvestKit"]),
    ]
)
