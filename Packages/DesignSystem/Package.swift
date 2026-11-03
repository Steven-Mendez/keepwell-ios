// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "es",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: [
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"],
        ),
    ],
    swiftLanguageModes: [.v6],
)
