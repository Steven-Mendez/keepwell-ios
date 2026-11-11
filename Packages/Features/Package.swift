// swift-tools-version: 6.2
// swiftlint:disable file_length
import PackageDescription

/// One folder per feature, split into Domain / Data / Presentation targets so the compiler
/// enforces the layer rules in `CLAUDE.md`. Shared entities and repositories live in the
/// `Domain` kernel and `Persistence`, so features only add a Data target when they own storage.
let package = Package(
    name: "Features",
    defaultLocalization: "en",
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
        .library(name: "SharedPresentation", targets: ["SharedPresentation"]),
        .library(name: "HomeDomain", targets: ["HomeDomain"]),
        .library(name: "HomePresentation", targets: ["HomePresentation"]),
        .library(name: "TransactionsDomain", targets: ["TransactionsDomain"]),
        .library(name: "TransactionsPresentation", targets: ["TransactionsPresentation"]),
        .library(name: "SummaryDomain", targets: ["SummaryDomain"]),
        .library(name: "SummaryPresentation", targets: ["SummaryPresentation"]),
        .library(name: "SettingsDomain", targets: ["SettingsDomain"]),
        .library(name: "SettingsPresentation", targets: ["SettingsPresentation"]),
        .library(name: "CreditCardDomain", targets: ["CreditCardDomain"]),
        .library(name: "CreditCardPresentation", targets: ["CreditCardPresentation"]),
        .library(name: "LockDomain", targets: ["LockDomain"]),
        .library(name: "LockPresentation", targets: ["LockPresentation"]),
        .library(name: "RecurringDomain", targets: ["RecurringDomain"]),
        .library(name: "RecurringPresentation", targets: ["RecurringPresentation"]),
        .library(name: "GoalsDomain", targets: ["GoalsDomain"]),
        .library(name: "GoalsPresentation", targets: ["GoalsPresentation"]),
        .library(name: "DebtsDomain", targets: ["DebtsDomain"]),
        .library(name: "DebtsPresentation", targets: ["DebtsPresentation"]),
        .library(name: "CloudAccountDomain", targets: ["CloudAccountDomain"]),
        .library(name: "CloudAccountData", targets: ["CloudAccountData"]),
        .library(name: "CloudAccountPresentation", targets: ["CloudAccountPresentation"]),
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
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "SharedPresentationTests",
            dependencies: [
                "SharedPresentation",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
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
            resources: [.process("Resources")],
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
            resources: [.process("Resources")],
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
            resources: [.process("Resources")],
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
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "CreateTransactionPresentationTests",
            dependencies: [
                "CreateTransactionPresentation",
                "CreateTransactionDomain",
                "FeatureTestSupport",
                .product(name: "DesignSystem", package: "DesignSystem"),
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

        // MARK: Home

        .target(
            name: "HomeDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Home/Domain",
        ),
        .target(
            name: "HomePresentation",
            dependencies: [
                "HomeDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
            path: "Sources/Home/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "HomePresentationTests",
            dependencies: [
                "HomePresentation",
                "HomeDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),
        .testTarget(
            name: "HomeDomainTests",
            dependencies: [
                "HomeDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Transactions

        .target(
            name: "TransactionsDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Transactions/Domain",
        ),
        .target(
            name: "TransactionsPresentation",
            dependencies: [
                "TransactionsDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
            path: "Sources/Transactions/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "TransactionsDomainTests",
            dependencies: [
                "TransactionsDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "TransactionsPresentationTests",
            dependencies: [
                "TransactionsPresentation",
                "TransactionsDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),

        // MARK: Summary

        .target(
            name: "SummaryDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Summary/Domain",
        ),
        .target(
            name: "SummaryPresentation",
            dependencies: [
                "SummaryDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
            path: "Sources/Summary/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "SummaryDomainTests",
            dependencies: [
                "SummaryDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Cloud account (Keepwell API: Sign in with Apple, session)

        .target(
            name: "CloudAccountDomain",
            path: "Sources/CloudAccount/Domain",
        ),
        .target(
            name: "CloudAccountData",
            dependencies: ["CloudAccountDomain", .product(name: "Domain", package: "Domain")],
            path: "Sources/CloudAccount/Data",
        ),
        .target(
            name: "CloudAccountPresentation",
            dependencies: [
                "CloudAccountDomain",
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
            path: "Sources/CloudAccount/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(name: "CloudAccountDomainTests", dependencies: ["CloudAccountDomain"]),
        .testTarget(
            name: "CloudAccountDataTests",
            dependencies: ["CloudAccountData", "CloudAccountDomain", .product(name: "Domain", package: "Domain")],
        ),
        .testTarget(
            name: "CloudAccountPresentationTests",
            dependencies: [
                "CloudAccountPresentation",
                "CloudAccountDomain",
                "OnboardingPresentation",
                "FeatureTestSupport",
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
            exclude: ["__Snapshots__"],
        ),

        // MARK: Settings

        .target(
            name: "SettingsDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Settings/Domain",
        ),
        .target(
            name: "SettingsPresentation",
            dependencies: [
                "SettingsDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
            path: "Sources/Settings/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "SettingsPresentationTests",
            dependencies: [
                "SettingsPresentation",
                "SettingsDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),
        .testTarget(
            name: "SettingsDomainTests",
            dependencies: [
                "SettingsDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Credit card

        .target(
            name: "CreditCardDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/CreditCard/Domain",
        ),
        .target(
            name: "CreditCardPresentation",
            dependencies: [
                "CreditCardDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
            path: "Sources/CreditCard/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "CreditCardPresentationTests",
            dependencies: [
                "CreditCardPresentation",
                "CreditCardDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "CreditCardDomainTests",
            dependencies: [
                "CreditCardDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Lock

        .target(
            name: "LockDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Lock/Domain",
        ),
        .target(
            name: "LockPresentation",
            dependencies: [
                "LockDomain",
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
            ],
            path: "Sources/Lock/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "LockDomainTests",
            dependencies: [
                "LockDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "LockPresentationTests",
            dependencies: [
                "LockPresentation",
                "LockDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Recurring

        .target(
            name: "RecurringDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Recurring/Domain",
        ),
        .target(
            name: "RecurringPresentation",
            dependencies: [
                "RecurringDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                // `#Preview` sample data only.
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/Recurring/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "RecurringDomainTests",
            dependencies: [
                "RecurringDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "RecurringPresentationTests",
            dependencies: [
                "RecurringPresentation",
                "RecurringDomain",
                "FeatureTestSupport",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
            exclude: ["__Snapshots__"],
        ),

        // MARK: Goals

        .target(
            name: "GoalsDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Goals/Domain",
        ),
        .target(
            name: "GoalsPresentation",
            dependencies: [
                "GoalsDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                // `#Preview` sample data only.
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/Goals/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "GoalsDomainTests",
            dependencies: [
                "GoalsDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "GoalsPresentationTests",
            dependencies: [
                "GoalsPresentation",
                "GoalsDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),

        // MARK: Debts

        .target(
            name: "DebtsDomain",
            dependencies: [.product(name: "Domain", package: "Domain")],
            path: "Sources/Debts/Domain",
        ),
        .target(
            name: "DebtsPresentation",
            dependencies: [
                "DebtsDomain",
                // Paying an installment records the expense through the same use case as the flow.
                "CreateTransactionDomain",
                "SharedPresentation",
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Domain", package: "Domain"),
                // `#Preview` sample data only.
                .product(name: "DomainSamples", package: "Domain"),
            ],
            path: "Sources/Debts/Presentation",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "DebtsDomainTests",
            dependencies: [
                "DebtsDomain",
                "CreateTransactionDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
        .testTarget(
            name: "DebtsPresentationTests",
            dependencies: [
                "DebtsPresentation",
                "DebtsDomain",
                "CreateTransactionDomain",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainSamples", package: "Domain"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
