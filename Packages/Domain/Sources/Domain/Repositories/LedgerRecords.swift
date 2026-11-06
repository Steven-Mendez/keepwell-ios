import Foundation

/// Everything the person has recorded, read together for screens that summarize across accounts.
public struct LedgerRecords: Sendable {
    public let accounts: [Account]
    public let cards: [Card]
    /// Newest first, as the repository returns them.
    public let transactions: [Transaction]
    public let categories: [TransactionCategory]

    public init(accounts: [Account], cards: [Card], transactions: [Transaction], categories: [TransactionCategory]) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
    }

    public static func load(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
    ) async throws(DomainError) -> Self {
        try await Self(
            accounts: accounts.fetchAccounts(),
            cards: cards.fetchCards(),
            transactions: transactions.fetchTransactions(in: nil),
            categories: categories.fetchCategories(),
        )
    }
}
