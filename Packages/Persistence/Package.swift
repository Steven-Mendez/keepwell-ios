// swift-tools-version: 6.2
import PackageDescription

/// On-device persistence with SwiftData, synced to the CloudKit private database.
/// Depends on each feature's Data target because the versioned schema must list every `@Model`.
let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(path: "../Features"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "TransactionsData", package: "Features"),
            ],
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
        ),
    ],
    swiftLanguageModes: [.v6],
)
