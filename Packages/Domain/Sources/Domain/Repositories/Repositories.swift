import Foundation

// Storage contracts shared by every feature. Data targets implement them; use cases receive
// them as protocols, so features never see SwiftData.

public protocol AccountRepository: Sendable {
    func fetchAccounts() async throws(DomainError) -> [Account]
    /// Inserts or replaces the account with the same id.
    func save(_ account: Account) async throws(DomainError)
    /// Soft-deletes: the record stays as a tombstone so the deletion syncs. Throws `.notFound`
    /// instead of succeeding silently, so the UI can't show a stale row as deleted.
    func deleteAccount(id: UUID) async throws(DomainError)
}

public protocol CardRepository: Sendable {
    func fetchCards() async throws(DomainError) -> [Card]
    func save(_ card: Card) async throws(DomainError)
    func deleteCard(id: UUID) async throws(DomainError)
}

public protocol TransactionRepository: Sendable {
    /// Newest first. `period` is half-open (`start` included, `end` excluded); `nil` returns everything.
    func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction]
    func save(_ transaction: Transaction) async throws(DomainError)
    /// Saves all of them in one save: a failure changes none.
    func save(_ transactions: [Transaction]) async throws(DomainError)
    func deleteTransaction(id: UUID) async throws(DomainError)
}

extension TransactionRepository {
    /// For stores with no atomic save of their own.
    public func save(_ transactions: [Transaction]) async throws(DomainError) {
        for transaction in transactions {
            try await save(transaction)
        }
    }
}

public protocol RecurringRuleRepository: Sendable {
    /// Live rules only, in the order they were created.
    func fetchRecurringRules() async throws(DomainError) -> [RecurringRule]
    /// Inserts or replaces the rule with the same id.
    func save(_ rule: RecurringRule) async throws(DomainError)
    /// Soft-deletes, like every other record. Throws `.notFound` for an unknown or deleted id.
    func deleteRecurringRule(id: UUID) async throws(DomainError)
    /// The movements one materialization run records and the rules it moves on, in a single save:
    /// a failure records nothing, so the next run tries the same occurrences again.
    func saveMaterialized(transactions: [Transaction], rules: [RecurringRule]) async throws(DomainError)
}

public protocol SavingsGoalRepository: Sendable {
    /// Live goals only, in the order they were created.
    func fetchSavingsGoals() async throws(DomainError) -> [SavingsGoal]
    /// Inserts or replaces the goal with the same id.
    func save(_ goal: SavingsGoal) async throws(DomainError)
    /// Soft-deletes, like every other record. Throws `.notFound` for an unknown or deleted id.
    func deleteSavingsGoal(id: UUID) async throws(DomainError)
}

public protocol LoanRepository: Sendable {
    /// Live loans only, in the order they were created.
    func fetchLoans() async throws(DomainError) -> [Loan]
    /// Inserts or replaces the loan with the same id.
    func save(_ loan: Loan) async throws(DomainError)
    /// Soft-deletes. Throws `.notFound` for an unknown or deleted id.
    func deleteLoan(id: UUID) async throws(DomainError)
    /// The movement that pays an installment and the loan that marks it paid, in a single save: a
    /// failure records neither, so an installment is never paid without its expense or twice.
    func save(_ loan: Loan, recording transaction: Transaction) async throws(DomainError)
    /// The loan with an installment back to due and the movement that paid it soft-deleted, in a
    /// single save. A movement already deleted (or `nil`) leaves only the loan to save.
    func save(_ loan: Loan, deletingTransaction transactionID: UUID?) async throws(DomainError)
}

public protocol PersonalDebtRepository: Sendable {
    /// Live debts only, in the order they were created.
    func fetchPersonalDebts() async throws(DomainError) -> [PersonalDebt]
    /// Inserts or replaces the debt with the same id.
    func save(_ debt: PersonalDebt) async throws(DomainError)
    /// Soft-deletes. Throws `.notFound` for an unknown or deleted id.
    func deletePersonalDebt(id: UUID) async throws(DomainError)
}

public protocol CategorizationRuleRepository: Sendable {
    /// Live rules in the person's order, which decides the one that wins.
    func fetchCategorizationRules() async throws(DomainError) -> [CategorizationRule]
    /// A new id goes after the existing ones; an existing one keeps its place.
    func save(_ rule: CategorizationRule) async throws(DomainError)
    /// Soft-deletes. Throws `.notFound` for an unknown or deleted id.
    func deleteCategorizationRule(id: UUID) async throws(DomainError)
    /// Stores this order; ids it leaves out keep their relative order after the listed ones.
    func reorderCategorizationRules(ids: [UUID]) async throws(DomainError)
}

public protocol MerchantRepository: Sendable {
    /// Live merchants (businesses and platforms), in no particular order.
    func fetchMerchants() async throws(DomainError) -> [Merchant]
    /// Inserts or replaces the merchant with the same id.
    func save(_ merchant: Merchant) async throws(DomainError)
    /// Soft-deletes. Throws `.notFound` for an unknown or deleted id.
    func deleteMerchant(id: UUID) async throws(DomainError)
    /// Every change of a merge, a deletion or a repair in a single save: a failure changes none, so
    /// nothing is left naming a merchant that is gone.
    func commit(_ changes: MerchantChanges) async throws(DomainError)
}

/// What deleting, merging or repairing merchants writes at once.
public struct MerchantChanges: Sendable {
    public var transactions: [Transaction]
    public var recurringRules: [RecurringRule]
    /// Saved in place: each keeps its position in the person's order.
    public var categorizationRules: [CategorizationRule]
    public var savedMerchants: [Merchant]
    public var deletedMerchantIDs: [UUID]

    public init(
        transactions: [Transaction] = [],
        recurringRules: [RecurringRule] = [],
        categorizationRules: [CategorizationRule] = [],
        savedMerchants: [Merchant] = [],
        deletedMerchantIDs: [UUID] = [],
    ) {
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.categorizationRules = categorizationRules
        self.savedMerchants = savedMerchants
        self.deletedMerchantIDs = deletedMerchantIDs
    }

    public var isEmpty: Bool {
        transactions.isEmpty && recurringRules.isEmpty && categorizationRules.isEmpty && savedMerchants.isEmpty
            && deletedMerchantIDs.isEmpty
    }
}

public protocol NotificationStateRepository: Sendable {
    /// Live states only: a pruned (tombstoned) one is gone for good.
    func fetchNotificationStates() async throws(DomainError) -> [NotificationState]
    /// Creates the state of an id never touched before. A change that leaves an existing state as
    /// it is writes nothing, so it never reaches the outbox.
    func apply(_ change: NotificationState.Change, to ids: [String]) async throws(DomainError)
    /// Tombstones the states whose id carries a day more than `NotificationState.retentionDays` old.
    func pruneNotificationStates(now: Date) async throws(DomainError)
}

public protocol CategoryRepository: Sendable {
    /// In the person's order. Includes every `TransactionCategory.defaults` entry, adding the ones
    /// a newer version ships, except the defaults the person deleted.
    func fetchCategories() async throws(DomainError) -> [TransactionCategory]
    /// A new id goes after the existing ones; an existing one keeps its place.
    func save(_ category: TransactionCategory) async throws(DomainError)
    /// A missing id succeeds: the same delete may already have arrived from another device.
    /// A default leaves a tombstone, so the next fetch doesn't add it back.
    func deleteCategory(id: String) async throws(DomainError)
    /// Stores this order; ids it leaves out keep their relative order after the listed ones.
    func reorderCategories(ids: [String]) async throws(DomainError)
    /// Every default back as shipped (name, icon, color and order), deleted ones included. The
    /// person's own categories stay, after the defaults.
    func restoreDefaultCategories() async throws(DomainError)
}

public protocol SettingsRepository: Sendable {
    /// `nil` before onboarding saves the first settings.
    func load() async throws(DomainError) -> Settings?
    func save(_ settings: Settings) async throws(DomainError)
}

/// "Eliminar todos mis datos": wipes this device (App Store guideline 5.1.1). Synced data on the
/// server goes with the account (Settings → Account → Delete account).
public protocol DataEraser: Sendable {
    func eraseAll() async throws(DomainError)
}

/// The app passcode, kept on this device only (never in the synced store). The
/// implementation stores a salted hash, so the code itself can't be read back.
public protocol PasscodeRepository: Sendable {
    func hasPasscode() async -> Bool
    func setPasscode(_ passcode: Passcode) async throws(DomainError)
    func verify(_ passcode: Passcode) async -> Bool
    /// Also clears the failed attempts.
    func removePasscode() async
    func attempts() async -> PasscodeAttempts
    func setAttempts(_ attempts: PasscodeAttempts) async
}

/// How the lock screen greets the person. Device-local, like the passcode it sits next to.
public protocol ProfileRepository: Sendable {
    /// `nil` when the person hasn't given one.
    func preferredName() async -> String?
    func setPreferredName(_ name: String?) async
}
