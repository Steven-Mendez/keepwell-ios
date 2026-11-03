import Domain
import Foundation
import SwiftData
import TransactionsDomain

/// Runs on its own `ModelContext` off the main thread. Only Domain structs leave the actor, because
/// `@Model` objects are not `Sendable`. `ModelActor` is conformed to by hand instead of with
/// `@ModelActor` so the initializer can be `public`.
public actor SwiftDataTransactionRepository: ModelActor, TransactionRepository {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
    }

    public func fetchTransactions(in period: DateInterval?) async throws(DomainError) -> [Transaction] {
        var descriptor = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let period {
            let start = period.start
            let end = period.end
            descriptor.predicate = #Predicate { $0.date >= start && $0.date < end }
        }
        var transactions: [Transaction] = []
        for record in try fetch(descriptor) {
            try transactions.append(record.toDomain())
        }
        return transactions
    }

    public func addTransaction(_ transaction: Transaction) async throws(DomainError) {
        modelContext.insert(transaction.toEntity())
        try save()
    }

    public func deleteTransaction(id: UUID) async throws(DomainError) {
        var descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try fetch(descriptor).first else { throw .notFound(id) }
        modelContext.delete(record)
        try save()
    }

    private func fetch(_ descriptor: FetchDescriptor<TransactionRecord>) throws(DomainError) -> [TransactionRecord] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw .persistence(String(describing: error))
        }
    }

    /// Rolls back on failure so a rejected insert/delete doesn't linger in the context and get
    /// written by the next unrelated save.
    private func save() throws(DomainError) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw .persistence(String(describing: error))
        }
    }
}
