import Domain
import Foundation

public protocol GetTransactionContextUseCase: Sendable {
    func execute() async throws(DomainError) -> TransactionContext
}

public struct DefaultGetTransactionContextUseCase: GetTransactionContextUseCase {
    private let settings: any SettingsRepository
    private let categories: any CategoryRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        settings: any SettingsRepository,
        categories: any CategoryRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.settings = settings
        self.categories = categories
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> TransactionContext {
        let currencies = try await settings.load()?.currencies ?? .fallbackForMovements
        let allAccounts = try await accounts.fetchAccounts()
        let allCards = try await cards.fetchCards()
        let movements = try await transactions.fetchTransactions(in: nil)

        var balances: [UUID: [Money]] = [:]
        for account in allAccounts {
            balances[account.id] = Balances.balance(of: account, transactions: movements, calendar: calendar)
        }
        var lastUsed: [PaymentSource: Date] = [:]
        var categoryUsage: [String: Int] = [:]
        for movement in movements {
            let source = movement.cardID.map(PaymentSource.card) ?? .account(movement.accountID)
            lastUsed[source] = max(lastUsed[source] ?? .distantPast, movement.date)
            if let category = movement.categoryID {
                categoryUsage[category, default: 0] += 1
            }
        }
        return try await TransactionContext(
            currencies: currencies,
            categories: categories.fetchCategories(),
            accounts: allAccounts,
            cards: allCards,
            balances: balances,
            lastUsed: lastUsed,
            categoryUsage: categoryUsage,
        )
    }
}

public protocol SaveTransactionUseCase: Sendable {
    func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction
}

public struct DefaultSaveTransactionUseCase: SaveTransactionUseCase {
    private let context: any GetTransactionContextUseCase
    private let transactions: any TransactionRepository
    private let calendar: Calendar

    public init(context: any GetTransactionContextUseCase, transactions: any TransactionRepository, calendar: Calendar = .current) {
        self.context = context
        self.transactions = transactions
        self.calendar = calendar
    }

    public func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction {
        let current = try await context.execute()
        let transaction = try Self.validated(draft, context: current)
        try await transactions.save(transaction)

        guard let account = current.account(transaction.accountID) else { throw .notFound(transaction.accountID) }
        let movements = try await transactions.fetchTransactions(in: nil)
        let newBalances = Balances.balance(of: account, transactions: movements, calendar: calendar)
        var categoryTotal: Money?
        if transaction.kind == .expense {
            let month = YearMonth(containing: transaction.date, calendar: calendar)
            let summary = MonthlySummary(month: month, transactions: movements, currency: current.currencies.principal, calendar: calendar)
            let total = summary.categories.first { $0.categoryID == transaction.categoryID }?.amount ?? 0
            categoryTotal = Money(total, current.currencies.principal)
        }
        return SavedTransaction(transaction: transaction, account: account, newBalances: newBalances, categoryMonthTotal: categoryTotal)
    }

    static func validated(_ draft: TransactionDraft, context: TransactionContext) throws(DomainError) -> Transaction {
        try Transaction.checkAmounts(draft.amount, actualDebitedPrincipal: draft.actualDebitedPrincipal)
        let currencies = context.currencies
        guard draft.currency == currencies.principal || draft.currency == currencies.second else {
            throw .invalidCurrency(draft.currency)
        }
        guard let source = draft.source, let accountID = context.accountID(for: source) else {
            throw .notFound(UUID(uuid: UUID_NULL))
        }

        var category: TransactionCategory?
        switch draft.kind {
        case .transfer:
            guard let destination = draft.destinationAccountID, destination != accountID, context.account(destination) != nil else {
                throw .invalidTransferDestination
            }
        case .expense, .income:
            guard let found = context.categories.first(where: { $0.id == draft.categoryID }) else {
                throw .notFound(UUID(uuid: UUID_NULL))
            }
            guard found.kind == draft.kind else { throw .categoryKindMismatch(expected: draft.kind, actual: found.kind) }
            category = found
        }

        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Transaction(
            id: draft.id,
            date: draft.date,
            status: .confirmed,
            // Safety net only: the view model fills a localized description before saving.
            description: description.isEmpty ? (category?.name ?? "Transfer") : description,
            kind: draft.kind,
            categoryID: draft.kind == .transfer ? nil : draft.categoryID,
            amount: draft.amount,
            currency: draft.currency,
            accountID: accountID,
            cardID: source.cardID,
            destinationAccountID: draft.kind == .transfer ? draft.destinationAccountID : nil,
            actualDebitedPrincipal: draft.currency == currencies.principal ? nil : draft.actualDebitedPrincipal,
            // The rate in force now travels with the movement, so later rate edits don't rewrite it.
            exchangeRate: currencies.exchangeRate,
            note: note.isEmpty ? nil : note,
        )
    }
}

extension CurrencySettings {
    static let fallbackForMovements: CurrencySettings = {
        guard let settings = try? CurrencySettings() else { preconditionFailure("Default currency settings are valid") }
        return settings
    }()
}
