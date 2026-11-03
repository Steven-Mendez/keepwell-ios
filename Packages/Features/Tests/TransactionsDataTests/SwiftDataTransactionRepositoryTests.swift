import Domain
import Foundation
import SwiftData
import Testing
@testable import TransactionsData
@testable import TransactionsDomain

@Suite("SwiftDataTransactionRepository")
struct SwiftDataTransactionRepositoryTests {
    private let repository: SwiftDataTransactionRepository

    init() throws {
        let container = try ModelContainer(
            for: TransactionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        )
        repository = SwiftDataTransactionRepository(modelContainer: container)
    }

    private static let category = TransactionCategory(id: "groceries", name: "Supermercado", kind: .expense)

    private static func transaction(_ amount: String, on date: Date, note: String? = nil) throws -> Transaction {
        try Transaction(
            amount: #require(Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))),
            currency: "NIO",
            kind: .expense,
            category: category,
            date: date,
            note: note,
            status: .planned,
        )
    }

    @Test
    func roundTripsEveryFieldWithExactDecimal() async throws {
        let original = try Self.transaction("12345678901234567.89", on: Date(timeIntervalSince1970: 1_772_000_000), note: "Nota")

        try await repository.addTransaction(original)
        let fetched = try await repository.fetchTransactions(in: nil)

        #expect(fetched == [original])
    }

    @Test
    func fetchesHalfOpenPeriodNewestFirst() async throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(1000)
        let atStart = try Self.transaction("1", on: start)
        let inside = try Self.transaction("2", on: start.addingTimeInterval(500))
        let atEnd = try Self.transaction("3", on: end)
        for transaction in [atStart, inside, atEnd] {
            try await repository.addTransaction(transaction)
        }

        let fetched = try await repository.fetchTransactions(in: DateInterval(start: start, end: end))

        #expect(fetched.map(\.id) == [inside.id, atStart.id])
    }

    @Test
    func deletesById() async throws {
        let transaction = try Self.transaction("5", on: .now)
        try await repository.addTransaction(transaction)

        try await repository.deleteTransaction(id: transaction.id)

        #expect(try await repository.fetchTransactions(in: nil).isEmpty)
    }

    @Test
    func deletingUnknownIdThrowsNotFound() async {
        let id = UUID()
        await #expect(throws: DomainError.notFound(id)) {
            try await repository.deleteTransaction(id: id)
        }
    }

    @Test
    func corruptedAmountFailsMapping() {
        let record = TransactionRecord(
            id: UUID(),
            amountString: "abc",
            currency: "USD",
            kindRaw: "expense",
            statusRaw: "confirmed",
            categoryID: "x",
            categoryName: "X",
            date: .now,
            note: nil,
        )

        #expect(throws: DomainError.self) { try record.toDomain() }
    }
}
