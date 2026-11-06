import Domain
import Foundation

/// Repository implementations kept in memory, for previews, snapshot tests and use case tests.
public actor InMemoryStore: AccountRepository, CardRepository, TransactionRepository, CategoryRepository,
    SettingsRepository, DataEraser, BackupStore
{
    private var accounts: [Account]
    private var cards: [Card]
    private var transactions: [Transaction]
    private var categories: [TransactionCategory]
    private var settings: Settings?

    public init(
        accounts: [Account] = [],
        cards: [Card] = [],
        transactions: [Transaction] = [],
        categories: [TransactionCategory] = TransactionCategory.defaults,
        settings: Settings? = nil,
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
    }

    public init(sample: SampleData) {
        self.init(
            accounts: sample.accounts,
            cards: sample.cards,
            transactions: sample.transactions,
            categories: sample.categories,
            settings: sample.settings,
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
    }

    /// Records here carry no history, so they export stamped with the moment of the export and a
    /// restore keeps only the live ones.
    public func exportContents() -> BackupContents {
        let stamp = RecordMetadata(createdAt: .now, updatedAt: .now)
        return BackupContents(
            settings: settings.map { Stamped($0, stamp) },
            accounts: accounts.map { Stamped($0, stamp) },
            cards: cards.map { Stamped($0, stamp) },
            categories: categories.map { Stamped($0, stamp) },
            transactions: transactions.map { Stamped($0, stamp) },
        )
    }

    public func replaceAll(with contents: BackupContents) {
        settings = contents.settings?.value
        accounts = contents.accounts.filter { !$0.metadata.isDeleted }.map(\.value)
        cards = contents.cards.filter { !$0.metadata.isDeleted }.map(\.value)
        categories = contents.categories.filter { !$0.metadata.isDeleted }.map(\.value)
        transactions = contents.transactions.filter { !$0.metadata.isDeleted }.map(\.value)
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
