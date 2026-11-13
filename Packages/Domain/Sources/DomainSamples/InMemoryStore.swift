import Domain
import Foundation

/// Repository implementations kept in memory, for previews, snapshot tests and use case tests.
public actor InMemoryStore: AccountRepository, CardRepository, TransactionRepository, CategoryRepository,
    SettingsRepository, DataEraser, RecurringRuleRepository, SavingsGoalRepository,
    LoanRepository, PersonalDebtRepository, CategorizationRuleRepository, NotificationStateRepository, MerchantRepository
{
    private var accounts: [Account]
    private var cards: [Card]
    private var transactions: [Transaction]
    private var categories: [TransactionCategory]
    private var settings: Settings?
    private var recurringRules: [RecurringRule]
    private var savingsGoals: [SavingsGoal]
    private var loans: [Loan]
    private var personalDebts: [PersonalDebt]
    /// Movements deposited by repayments no longer in `personalDebts` (deleted, alone or with their debt).
    private var removedRepaymentDeposits: [UUID] = []
    private var categorizationRules: [CategorizationRule]
    private var notificationStates: [String: NotificationState] = [:]
    private var merchants: [Merchant]

    public init(
        accounts: [Account] = [],
        cards: [Card] = [],
        transactions: [Transaction] = [],
        categories: [TransactionCategory] = TransactionCategory.defaults,
        settings: Settings? = nil,
        recurringRules: [RecurringRule] = [],
        savingsGoals: [SavingsGoal] = [],
        loans: [Loan] = [],
        personalDebts: [PersonalDebt] = [],
        categorizationRules: [CategorizationRule] = [],
        merchants: [Merchant] = [],
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.recurringRules = recurringRules
        self.savingsGoals = savingsGoals
        self.loans = loans
        self.personalDebts = personalDebts
        self.categorizationRules = categorizationRules
        self.merchants = merchants
    }

    public init(sample: SampleData) {
        self.init(
            accounts: sample.accounts,
            cards: sample.cards,
            transactions: sample.transactions,
            categories: sample.categories,
            settings: sample.settings,
            recurringRules: sample.recurringRules,
            savingsGoals: sample.savingsGoals,
            loans: sample.loans,
            personalDebts: sample.personalDebts,
            categorizationRules: sample.categorizationRules,
            merchants: sample.merchants,
        )
    }

    public func fetchAccounts() -> [Account] {
        accounts
    }

    public func save(_ account: Account) {
        upsert(account, into: &accounts)
    }

    public func deleteAccount(id: UUID) throws(DomainError) {
        try remove(id, from: &accounts)
    }

    public func fetchCards() -> [Card] {
        cards
    }

    public func save(_ card: Card) {
        upsert(card, into: &cards)
    }

    public func deleteCard(id: UUID) throws(DomainError) {
        try remove(id, from: &cards)
    }

    public func fetchTransactions(in period: DateInterval?) -> [Transaction] {
        transactions
            .filter { transaction in period.map { transaction.date >= $0.start && transaction.date < $0.end } ?? true }
            .sorted { $0.date > $1.date }
    }

    public func save(_ transaction: Transaction) {
        upsert(transaction, into: &transactions)
    }

    public func deleteTransaction(id: UUID) throws(DomainError) {
        try remove(id, from: &transactions)
    }

    public func fetchRecurringRules() -> [RecurringRule] {
        recurringRules
    }

    public func save(_ rule: RecurringRule) {
        upsert(rule, into: &recurringRules)
    }

    public func deleteRecurringRule(id: UUID) throws(DomainError) {
        try remove(id, from: &recurringRules)
    }

    public func save(_ transactions: [Transaction]) {
        for transaction in transactions {
            upsert(transaction, into: &self.transactions)
        }
    }

    public func saveMaterialized(transactions: [Transaction], rules: [RecurringRule]) {
        for transaction in transactions {
            upsert(transaction, into: &self.transactions)
        }
        for rule in rules {
            upsert(rule, into: &recurringRules)
        }
    }

    public func fetchSavingsGoals() -> [SavingsGoal] {
        savingsGoals
    }

    public func save(_ goal: SavingsGoal) {
        upsert(goal, into: &savingsGoals)
    }

    public func deleteSavingsGoal(id: UUID) throws(DomainError) {
        try remove(id, from: &savingsGoals)
    }

    public func fetchLoans() -> [Loan] {
        loans
    }

    public func save(_ loan: Loan) {
        upsert(loan, into: &loans)
    }

    public func deleteLoan(id: UUID) throws(DomainError) {
        try remove(id, from: &loans)
    }

    public func save(_ loan: Loan, recording transaction: Transaction) {
        upsert(transaction, into: &transactions)
        upsert(loan, into: &loans)
    }

    public func save(_ loan: Loan, deletingTransaction transactionID: UUID?) {
        transactions.removeAll { $0.id == transactionID }
        upsert(loan, into: &loans)
    }

    public func fetchPersonalDebts() -> [PersonalDebt] {
        personalDebts
    }

    public func save(_ debt: PersonalDebt) {
        storing(debt)
    }

    public func deletePersonalDebt(id: UUID) throws(DomainError) {
        forgetDeposits(of: personalDebts.first { $0.id == id }?.repayments ?? [])
        try remove(id, from: &personalDebts)
    }

    public func save(_ debt: PersonalDebt, recording transaction: Transaction) {
        upsert(transaction, into: &transactions)
        storing(debt)
    }

    public func save(_ debt: PersonalDebt, deletingTransaction transactionID: UUID?) {
        transactions.removeAll { $0.id == transactionID }
        storing(debt)
    }

    public func fetchCategorizationRules() -> [CategorizationRule] {
        categorizationRules
    }

    public func save(_ rule: CategorizationRule) {
        upsert(rule, into: &categorizationRules)
    }

    public func deleteCategorizationRule(id: UUID) throws(DomainError) {
        try remove(id, from: &categorizationRules)
    }

    public func reorderCategorizationRules(ids: [UUID]) {
        let rank = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let listed = categorizationRules.filter { rank[$0.id] != nil }.sorted { rank[$0.id] ?? 0 < rank[$1.id] ?? 0 }
        categorizationRules = listed + categorizationRules.filter { rank[$0.id] == nil }
    }

    public func fetchCategories() -> [TransactionCategory] {
        categories
    }

    public func save(_ category: TransactionCategory) {
        upsert(category, into: &categories)
    }

    /// Nothing re-adds missing defaults here, so removing the row is the whole tombstone.
    public func deleteCategory(id: String) {
        categories.removeAll { $0.id == id }
    }

    public func reorderCategories(ids: [String]) {
        let rank = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let listed = categories.filter { rank[$0.id] != nil }.sorted { rank[$0.id] ?? 0 < rank[$1.id] ?? 0 }
        categories = listed + categories.filter { rank[$0.id] == nil }
    }

    public func restoreDefaultCategories() {
        categories = TransactionCategory.defaults + categories.filter { !$0.isDefault }
    }

    public func load() -> Settings? {
        settings
    }

    public func save(_ settings: Settings) {
        self.settings = settings
    }

    public func eraseAll() {
        accounts = []
        cards = []
        transactions = []
        categories = []
        settings = nil
        recurringRules = []
        savingsGoals = []
        loans = []
        personalDebts = []
        removedRepaymentDeposits = []
        categorizationRules = []
        notificationStates = [:]
        merchants = []
    }

    public func fetchMerchants() -> [Merchant] {
        merchants
    }

    public func save(_ merchant: Merchant) {
        upsert(merchant, into: &merchants)
    }

    public func deleteMerchant(id: UUID) throws(DomainError) {
        try remove(id, from: &merchants)
    }

    /// An actor runs it whole, so it is as atomic as the store's single save.
    public func commit(_ changes: MerchantChanges) throws(DomainError) {
        for id in changes.deletedMerchantIDs where !merchants.contains(where: { $0.id == id }) {
            throw .notFound(id)
        }
        for transaction in changes.transactions {
            upsert(transaction, into: &transactions)
        }
        for rule in changes.recurringRules {
            upsert(rule, into: &recurringRules)
        }
        for rule in changes.categorizationRules {
            upsert(rule, into: &categorizationRules)
        }
        for merchant in changes.savedMerchants {
            upsert(merchant, into: &merchants)
        }
        merchants.removeAll { changes.deletedMerchantIDs.contains($0.id) }
        categories.removeAll { changes.deletedCategoryIDs.contains($0.id) }
    }

    public func fetchNotificationStates() -> [NotificationState] {
        notificationStates.values.sorted { $0.id < $1.id }
    }

    public func apply(_ change: NotificationState.Change, to ids: [String]) {
        for id in Set(ids) {
            notificationStates[id] = (notificationStates[id] ?? NotificationState(id: id)).applying(change, at: .now)
        }
    }

    public func pruneNotificationStates(now: Date) {
        notificationStates = notificationStates.filter { !NotificationState.isStale(id: $0.key, now: now) }
    }

    private func upsert<T: Identifiable>(_ item: T, into list: inout [T]) {
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
    }

    private func remove(_ id: UUID, from list: inout [some Identifiable<UUID>]) throws(DomainError) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw .notFound(id) }
        list.remove(at: index)
    }
}

/// Debt repayments that leave the store keep their deposits known.
extension InMemoryStore {
    public func fetchRepaymentDepositIDs() -> [UUID] {
        var seen = Set<UUID>()
        return (removedRepaymentDeposits + personalDebts.flatMap { $0.repayments.compactMap(\.transactionID) })
            .filter { seen.insert($0).inserted }
    }

    /// Repayments leaving the store keep their deposits known, as the database's tombstones do.
    private func storing(_ debt: PersonalDebt) {
        let kept = Set(debt.repayments.map(\.id))
        forgetDeposits(of: (personalDebts.first { $0.id == debt.id }?.repayments ?? []).filter { !kept.contains($0.id) })
        upsert(debt, into: &personalDebts)
    }

    private func forgetDeposits(of repayments: [DebtRepayment]) {
        removedRepaymentDeposits += repayments.compactMap(\.transactionID)
    }
}
