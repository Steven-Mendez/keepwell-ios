import Domain
import Foundation

/// "Reconcile": records the difference between the counted cash and the balance.
public protocol ReconcileCashUseCase: Sendable {
    /// Returns the adjustment saved, or `nil` when the count already matched.
    @discardableResult
    func execute(cash: AccountsOverview.Cash, counted: Decimal, description: String) async throws(DomainError) -> Transaction?
}

extension ReconcileCashUseCase {
    @discardableResult
    public func execute(cash: AccountsOverview.Cash, counted: Decimal) async throws(DomainError) -> Transaction? {
        try await execute(cash: cash, counted: counted, description: "Cash adjustment")
    }
}

public struct DefaultReconcileCashUseCase: ReconcileCashUseCase {
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let now: @Sendable () -> Date

    public init(transactions: any TransactionRepository, settings: any SettingsRepository, now: @escaping @Sendable () -> Date = { .now }) {
        self.transactions = transactions
        self.settings = settings
        self.now = now
    }

    @discardableResult
    public func execute(cash: AccountsOverview.Cash, counted: Decimal, description: String) async throws(DomainError) -> Transaction? {
        let rate = try await settings.load()?.currencies.exchangeRate ?? CurrencySettings.fallback.exchangeRate
        guard let adjustment = try CashReconciliation.adjustment(
            for: cash.account, balance: cash.balance, counted: counted, date: now(), exchangeRate: rate,
            description: description,
        ) else { return nil }
        try await transactions.save(adjustment)
        return adjustment
    }
}

/// "ATM withdrawal": a transfer from a bank account into cash, in the cash's currency, with
/// what the bank actually debited when it differs (rule 4).
public struct CashWithdrawal: Sendable {
    public let sourceAccountID: UUID
    public let cashAccountID: UUID
    public let amount: Money
    /// What the bank charged in the principal currency, when known.
    public let debitedPrincipal: Decimal?
    /// Persisted as the movement's text, so the caller passes it already in the user's language.
    public let description: String

    public init(
        sourceAccountID: UUID,
        cashAccountID: UUID,
        amount: Money,
        debitedPrincipal: Decimal?,
        description: String = "ATM withdrawal",
    ) {
        self.sourceAccountID = sourceAccountID
        self.cashAccountID = cashAccountID
        self.amount = amount
        self.debitedPrincipal = debitedPrincipal
        self.description = description
    }
}

public protocol WithdrawCashUseCase: Sendable {
    @discardableResult
    func execute(_ withdrawal: CashWithdrawal) async throws(DomainError) -> Transaction
}

public struct DefaultWithdrawCashUseCase: WithdrawCashUseCase {
    private let transactions: any TransactionRepository
    private let cards: any CardRepository
    private let settings: any SettingsRepository
    private let now: @Sendable () -> Date

    public init(
        transactions: any TransactionRepository,
        cards: any CardRepository,
        settings: any SettingsRepository,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.transactions = transactions
        self.cards = cards
        self.settings = settings
        self.now = now
    }

    @discardableResult
    public func execute(_ withdrawal: CashWithdrawal) async throws(DomainError) -> Transaction {
        guard withdrawal.amount.amount > 0, (withdrawal.debitedPrincipal ?? 1) > 0 else { throw .invalidAmount }
        guard withdrawal.sourceAccountID != withdrawal.cashAccountID else { throw .invalidTransferDestination }
        let rate = try await settings.load()?.currencies.exchangeRate ?? CurrencySettings.fallback.exchangeRate
        let transferMethod = try await cards.fetchCards().first { $0.accountID == withdrawal.sourceAccountID && $0.kind == .transfer }
        let transaction = Transaction(
            date: now(),
            description: withdrawal.description,
            kind: .transfer,
            categoryID: nil,
            amount: withdrawal.amount.amount,
            currency: withdrawal.amount.currency,
            accountID: withdrawal.sourceAccountID,
            cardID: transferMethod?.id,
            destinationAccountID: withdrawal.cashAccountID,
            actualDebitedPrincipal: withdrawal.debitedPrincipal,
            exchangeRate: rate,
        )
        try await transactions.save(transaction)
        return transaction
    }
}
