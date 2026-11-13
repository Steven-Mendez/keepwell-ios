// swift-tools-version: 6.2
import PackageDescription

/// On-device persistence with SwiftData, with the outbox the Keepwell account's sync pushes.
/// Implements the shared repository protocols from `Domain`.
let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(path: "../Domain"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [.product(name: "Domain", package: "Domain")],
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            // `wire-columns.json` and `sync-v1.json`, copied verbatim from keepwell-web's shared fixtures.
            resources: [.copy("Fixtures")],
        ),
    ],
    swiftLanguageModes: [.v6],
)
