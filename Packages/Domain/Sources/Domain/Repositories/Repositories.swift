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
    func deleteTransaction(id: UUID) async throws(DomainError)
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

/// "Eliminar todos mis datos": wipes this device and the iCloud copy (App Store guideline 5.1.1).
public protocol DataEraser: Sendable {
    func eraseAll() async throws(DomainError)
}

/// The whole store at once, deleted records and their metadata included, for the backup file
/// the iOS and web apps share.
public protocol BackupStore: Sendable {
    func exportContents() async throws(DomainError) -> BackupContents
    /// Replaces everything with `contents` in a single save: a failure leaves the store as it was.
    func replaceAll(with contents: BackupContents) async throws(DomainError)
}

/// The device-local "Respaldo en iCloud" switch. It decides which store opens at launch, so it
/// lives outside the synced settings.
public protocol BackupPreference: Sendable {
    var isICloudBackupEnabled: Bool { get }
    func setICloudBackupEnabled(_ isEnabled: Bool)
}

/// The app passcode, kept on this device only (never in the synced store or a backup). The
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
