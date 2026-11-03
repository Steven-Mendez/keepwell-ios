import Domain
import Foundation

public protocol TransactionRepository: Sendable {
    /// Newest first. `period` is half-open (`start` included, `end` excluded); `nil` returns everything.
    func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction]
    func addTransaction(_ transaction: Transaction) async throws(DomainError)
    /// Throws `.notFound` instead of succeeding silently, so the UI can't show a stale row as deleted.
    func deleteTransaction(id: UUID) async throws(DomainError)
}
