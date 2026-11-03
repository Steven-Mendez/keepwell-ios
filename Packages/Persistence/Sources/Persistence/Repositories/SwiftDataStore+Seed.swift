import Domain
import Foundation

extension SwiftDataStore {
    /// Writes a whole data set at once: UI tests and simulator runs launch with sample data, and a
    /// future restore from a file goes through the same path.
    public func seed(
        settings: Settings,
        accounts: [Account],
        cards: [Card],
        transactions: [Transaction],
        categories: [TransactionCategory],
    ) throws(DomainError) {
        try save(settings)
        for account in accounts {
            try save(account)
        }
        for card in cards {
            try save(card)
        }
        for transaction in transactions {
            try save(transaction)
        }
        for category in categories {
            try save(category)
        }
    }
}
