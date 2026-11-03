import Domain
import Foundation

public protocol AddTransactionUseCase: Sendable {
    /// Returns the transaction as stored (normalized currency and note).
    @discardableResult
    func execute(_ draft: Transaction) async throws(DomainError) -> Transaction
}

public struct DefaultAddTransactionUseCase: AddTransactionUseCase {
    private let repository: any TransactionRepository

    public init(repository: any TransactionRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(_ draft: Transaction) async throws(DomainError) -> Transaction {
        let transaction = try Self.validated(draft)
        try await repository.addTransaction(transaction)
        return transaction
    }

    static func validated(_ draft: Transaction) throws(DomainError) -> Transaction {
        // Direction lives in `kind`, so zero or negative amounts are always input errors.
        guard draft.amount > 0 else { throw .invalidAmount }

        let currency = draft.currency.trimmingCharacters(in: .whitespaces).uppercased()
        guard ISOCurrency.isValid(currency) else { throw .invalidCurrency(draft.currency) }

        guard draft.kind != .transfer else { throw .unsupportedTransactionKind(.transfer) }
        guard draft.category.kind == draft.kind else {
            throw .categoryKindMismatch(expected: draft.kind, actual: draft.category.kind)
        }

        let note = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Transaction(
            id: draft.id,
            amount: draft.amount,
            currency: currency,
            kind: draft.kind,
            category: draft.category,
            date: draft.date,
            note: note?.isEmpty == false ? note : nil,
            status: draft.status,
        )
    }
}
