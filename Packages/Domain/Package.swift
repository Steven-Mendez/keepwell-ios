// swift-tools-version: 6.2
import PackageDescription

/// Shared domain kernel used by every feature's Domain target. Foundation only, no third-party
/// code, so it ports directly to TypeScript.
let package = Package(
    name: "Domain",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
    ],
    targets: [
        .target(name: "Domain"),
        .testTarget(
            name: "DomainTests",
            dependencies: [
                "Domain",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
