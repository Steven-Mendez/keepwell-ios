// swift-tools-version: 6.2
import PackageDescription

/// Cross-feature app infrastructure: navigation, formatting and the hand-off to widgets. No business
/// rules, no persistence.
let package = Package(
    name: "Core",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ],
    swiftLanguageModes: [.v6],
)
