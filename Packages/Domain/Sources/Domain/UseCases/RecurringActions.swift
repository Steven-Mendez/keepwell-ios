import Foundation

// Recurring rules record movements from several places (the app coming to the foreground, a rule
// just saved, "repeat" on a new movement), so the run that records them lives in the kernel.

/// Records every recurring occurrence whose day has come, in one save.
public protocol MaterializeRecurringUseCase: Sendable {
    /// Returns how many movements were recorded.
    @discardableResult
    func execute() async throws(DomainError) -> Int
}

public struct DefaultMaterializeRecurringUseCase: MaterializeRecurringUseCase {
    private let rules: any RecurringRuleRepository
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let categorizationRules: (any CategorizationRuleRepository)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Accounts, cards and categories are there so a rule that no longer validates (its category,
    /// account or currency is gone) is skipped and left as it was, not recorded as bad data.
    /// `categorizationRules` categorizes an occurrence in "Other"; without it none is.
    public init(
        rules: any RecurringRuleRepository,
        transactions: any TransactionRepository,
        settings: any SettingsRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        categorizationRules: (any CategorizationRuleRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.rules = rules
        self.transactions = transactions
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.categorizationRules = categorizationRules
        self.calendar = calendar
        self.now = now
    }

    @discardableResult
    public func execute() async throws(DomainError) -> Int {
        let active = try await rules.fetchRecurringRules()
        guard !active.isEmpty else { return 0 }
        let currencies = try await settings.load()?.currencies ?? .initial
        let categories = try await categories.fetchCategories()
        let result = try await RecurringSchedule.materialize(
            validRules(active, currencies: currencies, categories: categories),
            transactions: transactions.fetchTransactions(in: nil),
            today: now(),
            // Today's rate, as any movement recorded today gets.
            exchangeRate: currencies.exchangeRate,
            calendar: calendar,
            categorizationRules: CategorizationRules.usable(
                categorizationRules?.fetchCategorizationRules() ?? [],
                categories: categories,
            ),
        )
        guard !result.isEmpty else { return 0 }
        try await rules.saveMaterialized(transactions: result.transactions, rules: result.rules)
        return result.transactions.count
    }

    private func validRules(
        _ all: [RecurringRule],
        currencies: CurrencySettings,
        categories: [TransactionCategory],
    ) async throws(DomainError) -> [RecurringRule] {
        let accounts = try await accounts.fetchAccounts()
        let cards = try await cards.fetchCards()
        return all.filter { rule in
            (try? rule.validated(
                currencies: currencies, accounts: accounts, cards: cards, categories: categories, calendar: calendar,
            )) != nil
        }
    }
}

/// Deletes a rule and the drafts it left waiting; what was already confirmed stays, since that
/// money really moved.
public protocol DeleteRecurringRuleUseCase: Sendable {
    func execute(id: UUID) async throws(DomainError)
}

public struct DefaultDeleteRecurringRuleUseCase: DeleteRecurringRuleUseCase {
    private let rules: any RecurringRuleRepository
    private let transactions: any TransactionRepository

    public init(rules: any RecurringRuleRepository, transactions: any TransactionRepository) {
        self.rules = rules
        self.transactions = transactions
    }

    public func execute(id: UUID) async throws(DomainError) {
        try await rules.deleteRecurringRule(id: id)
        for draft in try await transactions.fetchTransactions(in: nil) where draft.recurringID == id && !draft.isConfirmed {
            try await transactions.deleteTransaction(id: draft.id)
        }
    }
}
