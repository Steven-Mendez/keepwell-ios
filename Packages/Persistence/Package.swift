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
    targets: [
        .target(name: "Persistence"),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
        ),
    ],
    swiftLanguageModes: [.v6],
)
