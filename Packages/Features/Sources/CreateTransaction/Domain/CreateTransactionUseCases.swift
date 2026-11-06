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
    private let rules: (any CategorizationRuleRepository)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Without `rules`, no category comes from a rule.
    public init(
        settings: any SettingsRepository,
        categories: any CategoryRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        rules: (any CategorizationRuleRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.settings = settings
        self.categories = categories
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.rules = rules
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
            tagUsage: Tags.usage(in: movements),
            rules: rules?.fetchCategorizationRules() ?? [],
        )
    }
}

public protocol SaveTransactionUseCase: Sendable {
    func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction
}

public struct DefaultSaveTransactionUseCase: SaveTransactionUseCase {
    private let context: any GetTransactionContextUseCase
    private let transactions: any TransactionRepository
    private let recurringRules: (any RecurringRuleRepository)?
    private let materialize: (any MaterializeRecurringUseCase)?
    private let calendar: Calendar

    /// Without `recurringRules`, "Repeat" is ignored and only the movement is saved.
    public init(
        context: any GetTransactionContextUseCase,
        transactions: any TransactionRepository,
        recurringRules: (any RecurringRuleRepository)? = nil,
        materialize: (any MaterializeRecurringUseCase)? = nil,
        calendar: Calendar = .current,
    ) {
        self.context = context
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.materialize = materialize
        self.calendar = calendar
    }

    public func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction {
        let current = try await context.execute()
        var draft = draft
        if recurringRules == nil {
            draft.repeatFrequency = nil
        }
        let transaction = try Self.validated(draft, context: current)
        let rule = try draft.repeatFrequency.map { frequency throws(DomainError) in
            try Self.rule(repeating: transaction, every: frequency, id: draft.recurringRuleID, calendar: calendar)
        }
        try await transactions.save(transaction)
        if let rule, let recurringRules {
            try await recurringRules.save(rule)
            try await materialize?.execute()
        }

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
        try Transaction.checkCurrency(draft.currency, currencies: currencies)
        guard let source = draft.source, let accountID = context.accountID(for: source) else {
            throw .notFound(UUID(uuid: UUID_NULL))
        }

        var category: TransactionCategory?
        if draft.kind == .transfer {
            try Transaction.checkDestination(draft.destinationAccountID, from: accountID, accounts: context.accounts)
        } else {
            category = try Transaction.checkCategory(draft.categoryID, kind: draft.kind, categories: context.categories)
        }

        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Transaction(
            id: draft.id,
            date: draft.date,
            status: draft.isDraft ? .planned : .confirmed,
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
            recurringID: draft.repeatFrequency == nil ? nil : draft.recurringRuleID,
            tags: draft.tags,
        )
    }

    /// The rule "Repeat" saves: the movement as its first occurrence, the next one still ahead,
    /// waiting as drafts. A movement in "Subscriptions" makes it a subscription.
    static func rule(
        repeating transaction: Transaction,
        every frequency: RecurringFrequency,
        id: UUID,
        calendar: Calendar,
    ) throws(DomainError) -> RecurringRule {
        let first = RecurringRule(
            id: id,
            name: transaction.description,
            kind: transaction.kind,
            categoryID: transaction.categoryID,
            amount: transaction.amount,
            currency: transaction.currency,
            accountID: transaction.accountID,
            cardID: transaction.cardID,
            destinationAccountID: transaction.destinationAccountID,
            frequency: frequency,
            startDate: transaction.date,
            isSubscription: transaction.kind == .expense && transaction.categoryID == Subscriptions.categoryID,
            autoConfirm: false,
            note: transaction.note,
            tags: transaction.tags,
        )
        try first.checkSchedule(calendar: calendar)
        let next = RecurringSchedule.firstOccurrence(of: first, after: transaction.date, calendar: calendar) ?? transaction.date
        return first.with(nextDate: next)
    }
}

/// A movement checked and built exactly as saving builds it, without storing it, for callers that
/// store it in one write together with something else (a loan installment and the loan).
public protocol PrepareTransactionUseCase: Sendable {
    func execute(_ draft: TransactionDraft) async throws(DomainError) -> Transaction
}

public struct DefaultPrepareTransactionUseCase: PrepareTransactionUseCase {
    private let context: any GetTransactionContextUseCase

    public init(context: any GetTransactionContextUseCase) {
        self.context = context
    }

    public func execute(_ draft: TransactionDraft) async throws(DomainError) -> Transaction {
        var draft = draft
        draft.repeatFrequency = nil
        return try await DefaultSaveTransactionUseCase.validated(draft, context: context.execute())
    }
}

extension CurrencySettings {
    static let fallbackForMovements: CurrencySettings = {
        guard let settings = try? CurrencySettings() else { preconditionFailure("Default currency settings are valid") }
        return settings
    }()
}
