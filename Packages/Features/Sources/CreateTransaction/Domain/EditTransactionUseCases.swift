import Domain
import Foundation

/// A saved movement with what editing it, or showing its receipt again, needs.
public struct StoredTransaction: Sendable {
    public let transaction: Transaction
    /// The flow's context for this movement: its own rate stands in for the settings' (an edit
    /// keeps the rate it was recorded with), balances leave it out so its old version doesn't count
    /// next to the new one, and no categorization rule applies.
    public let context: TransactionContext
    /// Its receipt as things stand now.
    public let receipt: SavedTransaction

    public init(transaction: Transaction, context: TransactionContext, receipt: SavedTransaction) {
        self.transaction = transaction
        self.context = context
        self.receipt = receipt
    }
}

public protocol GetStoredTransactionUseCase: Sendable {
    func execute(id: UUID) async throws(DomainError) -> StoredTransaction
}

extension DefaultGetTransactionContextUseCase: GetStoredTransactionUseCase {
    public func execute(id: UUID) async throws(DomainError) -> StoredTransaction {
        let movements = try await transactions.fetchTransactions(in: nil)
        guard let transaction = movements.first(where: { $0.id == id }) else { throw .notFound(id) }
        let context = try await context(
            of: movements,
            excluding: id,
            currencies: CurrencySettings(recordedWith: transaction.exchangeRate),
            usesRules: false,
        )
        let receipt = try await DefaultSaveTransactionUseCase.receipt(
            of: transaction,
            accounts: context.accounts,
            movements: movements,
            principal: principalCurrency(),
            calendar: calendar,
            debts: personalDebts?.fetchPersonalDebts() ?? [],
        )
        return StoredTransaction(transaction: transaction, context: context, receipt: receipt)
    }
}

/// Saves the changes to a movement already stored, under the same rules as logging one. It keeps
/// its id, the rate it was recorded with, whether it's shared and the recurring rule behind it;
/// the account follows the payment method again and the description and note are trimmed again.
/// An edit never starts a recurring rule.
public protocol UpdateTransactionUseCase: Sendable {
    func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction
}

public struct DefaultUpdateTransactionUseCase: UpdateTransactionUseCase {
    private let stored: any GetStoredTransactionUseCase
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let merchants: (any MerchantRepository)?
    private let personalDebts: (any PersonalDebtRepository)?
    private let calendar: Calendar
    private let makeID: @Sendable () -> UUID

    /// Without `merchants`, a merchant the draft picked new isn't created. With `personalDebts`,
    /// the receipt's category total counts the person's part of split expenses.
    public init(
        stored: any GetStoredTransactionUseCase,
        transactions: any TransactionRepository,
        settings: any SettingsRepository,
        merchants: (any MerchantRepository)? = nil,
        personalDebts: (any PersonalDebtRepository)? = nil,
        calendar: Calendar = .current,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        self.stored = stored
        self.transactions = transactions
        self.settings = settings
        self.merchants = merchants
        self.personalDebts = personalDebts
        self.calendar = calendar
        self.makeID = makeID
    }

    public func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction {
        let current = try await stored.execute(id: draft.id)
        var draft = draft
        draft.repeatFrequency = nil
        var context = current.context
        let created = try DefaultSaveTransactionUseCase.creatingMerchants(
            &draft, context: &context, canCreate: merchants != nil, makeID: makeID,
        )
        let transaction = try DefaultSaveTransactionUseCase.validated(draft, context: context, existing: current.transaction)
        if let merchants, !created.isEmpty {
            // The new merchants and the movement in one save.
            try await merchants.commit(MerchantChanges(transactions: [transaction], savedMerchants: created))
        } else {
            try await transactions.save(transaction)
        }
        let principal = try await settings.load()?.currencies.principal ?? current.context.currencies.principal
        return try await DefaultSaveTransactionUseCase.receipt(
            of: transaction,
            accounts: current.context.accounts,
            movements: transactions.fetchTransactions(in: nil),
            principal: principal,
            calendar: calendar,
            debts: personalDebts?.fetchPersonalDebts() ?? [],
        )
    }
}

extension TransactionDraft {
    /// A draft that edits `transaction`, with every field as it was saved. Its charge in the
    /// principal currency (only a movement in another currency has one) keeps what it was charged
    /// for, so changing the amount, currency or account drops it instead of leaving a stale charge
    /// driving balances.
    public init(editing transaction: Transaction) {
        let charged = transaction.currency == transaction.exchangeRate.principal ? nil : transaction.actualDebitedPrincipal
        self.init(
            id: transaction.id,
            kind: transaction.kind,
            amount: transaction.amount,
            currency: transaction.currency,
            categoryID: transaction.categoryID,
            source: transaction.cardID.map(PaymentSource.card) ?? .account(transaction.accountID),
            destinationAccountID: transaction.destinationAccountID,
            description: transaction.description,
            date: transaction.date,
            actualDebitedPrincipal: charged,
            debitedFor: charged.map { _ in
                DebitedFor(amount: transaction.amount, currency: transaction.currency, accountID: transaction.accountID)
            },
            note: transaction.note ?? "",
            isDraft: !transaction.isConfirmed,
            tags: transaction.tags,
            merchant: MerchantLink(transaction.merchantID),
            via: MerchantLink(transaction.viaMerchantID),
        )
    }
}

extension CurrencySettings {
    /// The currencies a stored rate converts between, so an edit offers exactly those.
    init(recordedWith rate: ExchangeRate) {
        self = (try? CurrencySettings(principal: rate.principal, second: rate.second, rate: rate.rate)) ?? .fallbackForMovements
    }
}
