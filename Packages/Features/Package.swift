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
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Domain"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    ],
    targets: [
        // MARK: Onboarding

        .target(
            name: "OnboardingDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Onboarding/Domain",
        ),
        .testTarget(
            name: "OnboardingDomainTests",
            dependencies: [
                "OnboardingDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
