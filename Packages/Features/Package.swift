// swift-tools-version: 6.2
import PackageDescription

/// One folder per feature, split into Domain / Data / Presentation targets so the compiler
/// enforces the layer rules in `CLAUDE.md`.
let package = Package(
    name: "Features",
    defaultLocalization: "es",
    platforms: [.iOS(.v26)],
    products: [],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Domain"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.7.3"),
    ],
    targets: [],
    swiftLanguageModes: [.v6],
)
