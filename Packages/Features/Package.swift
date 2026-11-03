// swift-tools-version: 6.2
import PackageDescription

/// One folder per feature, split into Domain / Data / Presentation targets so the compiler
/// enforces the layer rules in `CLAUDE.md`. Shared entities and repositories live in the
/// `Domain` kernel and `Persistence`, so features only add a Data target when they own storage.
let package = Package(
    name: "Features",
    defaultLocalization: "es",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "OnboardingDomain", targets: ["OnboardingDomain"]),
        .library(name: "OnboardingPresentation", targets: ["OnboardingPresentation"]),
        .library(name: "AccountsDomain", targets: ["AccountsDomain"]),
        .library(name: "AccountsPresentation", targets: ["AccountsPresentation"]),
        .library(name: "AddCardDomain", targets: ["AddCardDomain"]),
        .library(name: "AddCardPresentation", targets: ["AddCardPresentation"]),
        .library(name: "CreateTransactionDomain", targets: ["CreateTransactionDomain"]),
        .library(name: "CreateTransactionPresentation", targets: ["CreateTransactionPresentation"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Domain"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    ],
    targets: [
        // Snapshot helpers shared by the Presentation test targets.
        .target(
            name: "FeatureTestSupport",
            dependencies: [
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/FeatureTestSupport",
        ),

        // Display mappings (cards, money, categories) shared by the Presentation targets.
        .target(
            name: "SharedPresentation",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "SharedPresentationTests",
            dependencies: ["SharedPresentation", .product(name: "Domain", package: "Domain"), .product(name: "Core", package: "Core")],
        ),

        // MARK: Onboarding

        .target(
            name: "OnboardingDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Onboarding/Domain",
        ),
        .target(
            name: "OnboardingPresentation",
            dependencies: [
                "OnboardingDomain",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                // `#Preview` sample data only.
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/Onboarding/Presentation",
        ),
        .testTarget(
            name: "OnboardingDomainTests",
            dependencies: [
                "OnboardingDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "OnboardingPresentationTests",
            dependencies: [
                "OnboardingPresentation",
                "OnboardingDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),

        // MARK: Accounts

        .target(
            name: "AccountsDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Accounts/Domain",
        ),
        .target(
            name: "AccountsPresentation",
            dependencies: [
                "AccountsDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/Accounts/Presentation",
        ),
        .testTarget(
            name: "AccountsPresentationTests",
            dependencies: [
                "AccountsPresentation",
                "AccountsDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),
        .testTarget(
            name: "AccountsDomainTests",
            dependencies: [
                "AccountsDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Add card

        .target(
            name: "AddCardDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/AddCard/Domain",
        ),
        .target(
            name: "AddCardPresentation",
            dependencies: [
                "AddCardDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/AddCard/Presentation",
        ),
        .testTarget(
            name: "AddCardPresentationTests",
            dependencies: [
                "AddCardPresentation",
                "AddCardDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),
        .testTarget(
            name: "AddCardDomainTests",
            dependencies: [
                "AddCardDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Create transaction

        .target(
            name: "CreateTransactionDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/CreateTransaction/Domain",
        ),
        .target(
            name: "CreateTransactionPresentation",
            dependencies: [
                "CreateTransactionDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/CreateTransaction/Presentation",
        ),
        .testTarget(
            name: "CreateTransactionPresentationTests",
            dependencies: [
                "CreateTransactionPresentation",
                "CreateTransactionDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),
        .testTarget(
            name: "CreateTransactionDomainTests",
            dependencies: [
                "CreateTransactionDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
