import Domain
import Foundation

public protocol DeleteTransactionUseCase: Sendable {
    func execute(id: UUID) async throws(DomainError)
}

public struct DefaultDeleteTransactionUseCase: DeleteTransactionUseCase {
    private let repository: any TransactionRepository

    public init(repository: any TransactionRepository) {
        self.repository = repository
    }

    public func execute(id: UUID) async throws(DomainError) {
        try await repository.deleteTransaction(id: id)
    }
}
