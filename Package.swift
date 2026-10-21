// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure Foundation: parsing and display logic, unit tested.
        .target(name: "QuotaCore"),
        // AppKit/SwiftUI/WebKit menu bar app.
        .executableTarget(name: "JokenBar", dependencies: ["QuotaCore"]),
        .testTarget(
            name: "QuotaCoreTests",
            dependencies: ["QuotaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
