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
        case .other: "Card"
        }
    }
}

/// The card a bank account is created with. A bank account is shown and used as its card, so it
/// always gets one; without digits it still exists and can be filled in later.
public struct DebitCardDraft: Sendable, Equatable {
    public var lastFour: String?
    public var network: CardNetwork?
    public var color: CardColor

    public init(lastFour: String? = nil, network: CardNetwork? = nil, color: CardColor = .coral) {
        self.lastFour = lastFour
        self.network = network
        self.color = color
    }
}

/// "Debit card" (a bank account with its card) and "Other wallet" from the add menu.
public protocol AddAccountUseCase: Sendable {
    /// `debitCard` is used for bank accounts only; cash has no card.
    func execute(
        kind: AccountKind,
        name: String,
        bank: String?,
        balance: Money,
        debitCard: DebitCardDraft,
    ) async throws(DomainError) -> Account
}

extension AddAccountUseCase {
    public func execute(kind: AccountKind, name: String, bank: String?, balance: Money) async throws(DomainError) -> Account {
        try await execute(kind: kind, name: name, bank: bank, balance: balance, debitCard: DebitCardDraft())
    }
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

    public func execute(
        kind: AccountKind,
        name: String,
        bank: String?,
        balance: Money,
        debitCard: DebitCardDraft,
    ) async throws(DomainError) -> Account {
        guard kind != .credit else { throw .unsupportedTransactionKind(.transfer) }
        guard balance.amount >= 0 else { throw .invalidAmount }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw .missingName }
        let trimmedBank = bank?.trimmingCharacters(in: .whitespaces)
        let account = Account(
            name: trimmed,
            bank: trimmedBank?.isEmpty == false ? trimmedBank : nil,
            kind: kind,
            openingBalances: [balance],
            openingDate: now(),
        )
        // Built before saving anything, so bad digits leave no account without its card.
        let methods: [Card] = kind == .deposit
            ? try [
                Card.debit(for: account.id, lastFour: debitCard.lastFour, network: debitCard.network, color: debitCard.color),
                Card(accountID: account.id, kind: .transfer),
            ]
            : []
        try await accounts.save(account)
        for method in methods {
            try await cards.save(method)
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
