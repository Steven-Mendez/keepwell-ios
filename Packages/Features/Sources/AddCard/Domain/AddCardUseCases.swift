import Domain
import Foundation

/// A credit card as entered in the add-card flow.
public struct CreditCardDraft: Sendable {
    public var bank: String
    public var lastFour: String
    public var network: CardNetwork
    public var color: CardColor
    public var debtMode: DebtMode
    /// What is owed today, positive, in the principal currency (or the only currency of the card).
    public var principalDebt: Decimal
    /// Dual cards: what is owed in the second currency.
    public var secondDebt: Decimal
    public var limit: Decimal?
    public var cutoffDay: Int
    public var dueDay: Int

    public init(
        bank: String,
        lastFour: String,
        network: CardNetwork,
        color: CardColor,
        debtMode: DebtMode,
        principalDebt: Decimal = 0,
        secondDebt: Decimal = 0,
        limit: Decimal? = nil,
        cutoffDay: Int,
        dueDay: Int,
    ) {
        self.bank = bank
        self.lastFour = lastFour
        self.network = network
        self.color = color
        self.debtMode = debtMode
        self.principalDebt = principalDebt
        self.secondDebt = secondDebt
        self.limit = limit
        self.cutoffDay = cutoffDay
        self.dueDay = dueDay
    }
}

public protocol AddCreditCardUseCase: Sendable {
    /// Creates the credit account and its holder plastic.
    func execute(_ draft: CreditCardDraft) async throws(DomainError) -> (account: Account, holder: Card)
}

public struct DefaultAddCreditCardUseCase: AddCreditCardUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let settings: any SettingsRepository
    private let now: @Sendable () -> Date

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        settings: any SettingsRepository,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.accounts = accounts
        self.cards = cards
        self.settings = settings
        self.now = now
    }

    public func execute(_ draft: CreditCardDraft) async throws(DomainError) -> (account: Account, holder: Card) {
        guard draft.principalDebt >= 0, draft.secondDebt >= 0, (draft.limit ?? 1) > 0 else { throw .invalidAmount }
        let currencies = try await settings.load()?.currencies ?? CurrencySettings.fallbackForCards
        let second = currencies.second ?? currencies.principal
        let mode = currencies.second == nil ? .principal : draft.debtMode
        // Debts are negative balances (rule 5).
        let openingBalances: [Money] = switch mode {
        case .dual: [Money(-draft.principalDebt, currencies.principal), Money(-draft.secondDebt, second)]
        case .principal: [Money(-draft.principalDebt, currencies.principal)]
        case .second: [Money(-draft.principalDebt, second)]
        }
        let limitCurrency = mode == .second ? second : currencies.principal
        let terms = try CreditTerms(
            debtMode: mode,
            limit: draft.limit.map { Money($0, limitCurrency) },
            cutoffDay: draft.cutoffDay,
            dueDay: draft.dueDay,
        )
        let bank = draft.bank.trimmingCharacters(in: .whitespaces)
        let account = Account(
            name: Self.networkName(draft.network),
            bank: bank.isEmpty ? nil : bank,
            kind: .credit,
            openingBalances: openingBalances,
            openingDate: now(),
            creditTerms: terms,
        )
        let holder = try Card(
            accountID: account.id,
            kind: .creditHolder,
            network: draft.network,
            lastFour: draft.lastFour,
            color: draft.color,
        )
        try await accounts.save(account)
        try await cards.save(holder)
        return (account, holder)
    }

    static func networkName(_ network: CardNetwork) -> String {
        switch network {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .amex: "Amex"
        case .other: "Tarjeta"
        }
    }
}

public protocol AddDebitCardUseCase: Sendable {
    func execute(accountID: UUID, lastFour: String, network: CardNetwork, color: CardColor) async throws(DomainError) -> Card
}

public struct DefaultAddDebitCardUseCase: AddDebitCardUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository

    public init(accounts: any AccountRepository, cards: any CardRepository) {
        self.accounts = accounts
        self.cards = cards
    }

    public func execute(accountID: UUID, lastFour: String, network: CardNetwork, color: CardColor) async throws(DomainError) -> Card {
        guard let account = try await accounts.fetchAccounts().first(where: { $0.id == accountID }) else {
            throw .notFound(accountID)
        }
        // Debit cards draw from a bank account; a credit card's plastics come from its own flow.
        guard account.kind == .deposit else { throw .invalidTransferDestination }
        let card = try Card(accountID: accountID, kind: .debit, network: network, lastFour: lastFour, color: color)
        try await cards.save(card)
        return card
    }
}

/// "Cuenta de banco" and "Otra billetera" from the add menu.
public protocol AddAccountUseCase: Sendable {
    func execute(kind: AccountKind, name: String, bank: String?, balance: Money) async throws(DomainError) -> Account
}

public struct DefaultAddAccountUseCase: AddAccountUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let now: @Sendable () -> Date

    public init(accounts: any AccountRepository, cards: any CardRepository, now: @escaping @Sendable () -> Date = { .now }) {
        self.accounts = accounts
        self.cards = cards
        self.now = now
    }

    public func execute(kind: AccountKind, name: String, bank: String?, balance: Money) async throws(DomainError) -> Account {
        guard kind != .credit else { throw .unsupportedTransactionKind(.transfer) }
        guard balance.amount >= 0 else { throw .invalidAmount }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw .corruptedData("Empty account name") }
        let account = Account(name: trimmed, bank: bank, kind: kind, openingBalances: [balance], openingDate: now())
        try await accounts.save(account)
        if kind == .deposit {
            try await cards.save(Card(accountID: account.id, kind: .transfer))
        }
        return account
    }
}

extension CurrencySettings {
    static let fallbackForCards: CurrencySettings = {
        guard let settings = try? CurrencySettings() else { preconditionFailure("Default currency settings are valid") }
        return settings
    }()
}
