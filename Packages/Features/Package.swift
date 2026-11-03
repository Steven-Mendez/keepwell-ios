// swift-tools-version: 6.2
import PackageDescription

/// One folder per feature, split into Domain / Data / Presentation targets so the compiler
/// enforces the layer rules in `CLAUDE.md`.
let package = Package(
    name: "Features",
    defaultLocalization: "es",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TransactionsDomain", targets: ["TransactionsDomain"]),
        .library(name: "TransactionsData", targets: ["TransactionsData"]),
        .library(name: "TransactionsPresentation", targets: ["TransactionsPresentation"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Domain"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
    ],
    targets: [
        .target(
            name: "TransactionsDomain",
            dependencies: ["Domain"],
            path: "Sources/Transactions/Domain",
        ),
        .target(
            name: "TransactionsData",
            dependencies: ["Domain", "TransactionsDomain"],
            path: "Sources/Transactions/Data",
        ),
        .target(
            name: "TransactionsPresentation",
            dependencies: [
                "Core",
                "DesignSystem",
                "Domain",
                "TransactionsDomain",
                // `#Preview` only (in-memory repository); imported under `#if DEBUG`.
                "TransactionsData",
            ],
            path: "Sources/Transactions/Presentation",
        ),
        .testTarget(
            name: "TransactionsDomainTests",
            dependencies: [
                "Domain",
                "TransactionsDomain",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ],
        ),
        .testTarget(
            name: "TransactionsDataTests",
            dependencies: ["Domain", "TransactionsDomain", "TransactionsData"],
        ),
        .testTarget(
            name: "TransactionsPresentationTests",
            dependencies: ["Domain", "TransactionsDomain", "TransactionsPresentation"],
        ),
    ],
    swiftLanguageModes: [.v6],
)
