import Domain
import Foundation

/// What the settings screen shows besides the settings themselves.
public struct SettingsOverview: Hashable, Sendable {
    public let settings: Settings
    public let expenseCategoryCount: Int
    public let incomeCategoryCount: Int
    /// Cards and transfer channels.
    public let paymentMethodCount: Int
    public let categorizationRuleCount: Int
    /// Only while there are no accounts and no movements.
    public let canChangeMainCurrency: Bool
    /// Only while no balance or movement is kept in it.
    public let canChangeSecondCurrency: Bool
    /// Whether this iPhone has an app passcode; it's device-local, so not part of `settings`.
    public let hasPasscode: Bool
    /// The name the lock screen greets with.
    public let preferredName: String?

    public init(
        settings: Settings,
        expenseCategoryCount: Int,
        incomeCategoryCount: Int,
        paymentMethodCount: Int,
        categorizationRuleCount: Int = 0,
        canChangeMainCurrency: Bool = false,
        canChangeSecondCurrency: Bool = false,
        hasPasscode: Bool = false,
        preferredName: String? = nil,
    ) {
        self.hasPasscode = hasPasscode
        self.preferredName = preferredName
        self.settings = settings
        self.expenseCategoryCount = expenseCategoryCount
        self.incomeCategoryCount = incomeCategoryCount
        self.paymentMethodCount = paymentMethodCount
        self.categorizationRuleCount = categorizationRuleCount
        self.canChangeMainCurrency = canChangeMainCurrency
        self.canChangeSecondCurrency = canChangeSecondCurrency
    }
}

public protocol GetSettingsOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> SettingsOverview
}

public struct DefaultGetSettingsOverviewUseCase: GetSettingsOverviewUseCase {
    private let settings: any SettingsRepository
    private let categories: any CategoryRepository
    private let cards: any CardRepository
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let rules: any CategorizationRuleRepository
    private let passcodes: (any PasscodeRepository)?
    private let profile: (any ProfileRepository)?

    public init(
        settings: any SettingsRepository,
        categories: any CategoryRepository,
        cards: any CardRepository,
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        rules: any CategorizationRuleRepository,
        passcodes: (any PasscodeRepository)? = nil,
        profile: (any ProfileRepository)? = nil,
    ) {
        self.passcodes = passcodes
        self.profile = profile
        self.settings = settings
        self.categories = categories
        self.cards = cards
        self.accounts = accounts
        self.transactions = transactions
        self.rules = rules
    }

    public func execute() async throws(DomainError) -> SettingsOverview {
        let current = try await settings.load() ?? Settings(currencies: .initial)
        let allCategories = try await categories.fetchCategories()
        let allAccounts = try await accounts.fetchAccounts()
        let allTransactions = try await transactions.fetchTransactions(in: nil)
        return try await SettingsOverview(
            settings: current,
            expenseCategoryCount: allCategories.count { $0.kind == .expense },
            incomeCategoryCount: allCategories.count { $0.kind == .income },
            paymentMethodCount: cards.fetchCards().count,
            categorizationRuleCount: rules.fetchCategorizationRules().count,
            canChangeMainCurrency: CurrencyUsage.canChangeMain(accounts: allAccounts, transactions: allTransactions),
            canChangeSecondCurrency: CurrencyUsage.canChangeSecond(
                current.currencies.second, accounts: allAccounts, transactions: allTransactions,
            ),
            hasPasscode: passcodes?.hasPasscode() ?? false,
            preferredName: profile?.preferredName(),
        )
    }
}

/// Saves a change to the settings. Changes to the rate only affect movements recorded from now
/// on: each movement keeps the rate it was recorded with (rule 2).
public protocol UpdateSettingsUseCase: Sendable {
    func execute(_ change: @Sendable (inout Settings) throws(DomainError) -> Void) async throws(DomainError) -> Settings
}

public struct DefaultUpdateSettingsUseCase: UpdateSettingsUseCase {
    private let settings: any SettingsRepository

    public init(settings: any SettingsRepository) {
        self.settings = settings
    }

    public func execute(_ change: @Sendable (inout Settings) throws(DomainError) -> Void) async throws(DomainError) -> Settings {
        var updated = try await settings.load() ?? Settings(currencies: .initial)
        try change(&updated)
        try await settings.save(updated)
        return updated
    }
}

extension Settings {
    /// Replaces the manual rate, keeping both currencies.
    public mutating func setRate(_ rate: Decimal) throws(DomainError) {
        currencies = try CurrencySettings(principal: currencies.principal, second: currencies.second, rate: rate)
    }

    /// Makes the second currency the main one: net worth, summaries and new movements follow it.
    public mutating func swapCurrencies() throws(DomainError) {
        guard let swapped = currencies.swapped() else { throw .invalidExchangeRate }
        currencies = swapped
    }
}

/// Turns the app passcode off; the lock goes back to Face ID or the iPhone passcode.
public protocol RemovePasscodeUseCase: Sendable {
    func execute() async
}

public struct DefaultRemovePasscodeUseCase: RemovePasscodeUseCase {
    private let passcodes: any PasscodeRepository

    public init(passcodes: any PasscodeRepository) {
        self.passcodes = passcodes
    }

    public func execute() async {
        await passcodes.removePasscode()
    }
}

/// "Delete all my data": everything on this device (App Store guideline 5.1.1). Data synced to
/// the Keepwell account is deleted with the account.
public protocol EraseAllDataUseCase: Sendable {
    func execute() async throws(DomainError)
}

public struct DefaultEraseAllDataUseCase: EraseAllDataUseCase {
    private let eraser: any DataEraser

    public init(eraser: any DataEraser) {
        self.eraser = eraser
    }

    public func execute() async throws(DomainError) {
        try await eraser.eraseAll()
    }
}
