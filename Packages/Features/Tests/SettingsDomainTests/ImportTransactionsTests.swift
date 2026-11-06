import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Import CSV")
struct ImportTransactionsTests {
    private let sample = SampleData.standard

    private func importer(_ store: InMemoryStore) -> DefaultImportTransactionsUseCase {
        DefaultImportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store, settings: store)
    }

    private func exported(from store: InMemoryStore) async throws -> String {
        try await DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store).execute()
    }

    @Test
    func anExportImportsBackIntoAnEmptyLedger() async throws {
        let original = InMemoryStore(sample: sample)
        let csv = try await exported(from: original)
        let empty = InMemoryStore(sample: sample)
        for transaction in sample.transactions {
            try await empty.deleteTransaction(id: transaction.id)
        }
        let summary = try await importer(empty).execute(csv: csv)
        #expect(summary.imported == sample.transactions.count)
        #expect(summary.skipped == 0)
        let restored = await empty.fetchTransactions(in: nil)
        #expect(restored.reduce(Decimal(0)) { $0 + $1.amount } == sample.transactions.reduce(Decimal(0)) { $0 + $1.amount })
        #expect(Set(restored.map(\.categoryID)) == Set(sample.transactions.map(\.categoryID)))
    }

    @Test
    func importingTheSameFileTwiceAddsNothing() async throws {
        let store = InMemoryStore(sample: sample)
        let summary = try await importer(store).execute(csv: exported(from: store))
        #expect(summary.imported == 0)
        #expect(summary.skipped == sample.transactions.count)
        #expect(await store.fetchTransactions(in: nil).count == sample.transactions.count)
    }

    @Test
    func rowsForUnknownAccountsAreSkippedNotGuessed() async throws {
        let store = InMemoryStore(sample: sample)
        let csv = """
        date,type,description,amount,currency,account
        2026-10-01,expense,Coffee,3.50,USD,Some Other Bank
        """
        let summary = try await importer(store).execute(csv: csv)
        #expect(summary == ImportSummary(imported: 0, skipped: 1))
    }

    @Test
    func rowsWithANonPositiveBankChargeAreSkipped() async throws {
        let store = InMemoryStore(sample: sample)
        let cash = try #require(sample.accounts.first { $0.id == SampleData.IDs.cash })
        let csv = """
        date,type,description,amount,currency,account,debited_principal
        2026-10-01,expense,Lunch,250,NIO,\(cash.name),-6.83
        2026-10-01,expense,Dinner,0,NIO,\(cash.name),
        """
        let summary = try await importer(store).execute(csv: csv)
        #expect(summary == ImportSummary(imported: 0, skipped: 2))
    }

    @Test
    func unknownCategoriesLandInOther() async throws {
        let store = InMemoryStore(sample: sample)
        let cash = try #require(sample.accounts.first { $0.id == SampleData.IDs.cash })
        let csv = """
        date,type,description,category,amount,currency,account
        2026-10-02,expense,Snacks,Something new,40,NIO,\(cash.name)
        """
        let summary = try await importer(store).execute(csv: csv)
        #expect(summary.imported == 1)
        let saved = try #require(await store.fetchTransactions(in: nil).first { $0.description == "Snacks" })
        #expect(saved.categoryID == TransactionCategory.otherExpenseID)
        #expect(saved.accountID == cash.id)
    }

    @Test
    func quotedFieldsKeepTheirCommasQuotesAndLineBreaks() {
        let rows = CSV.rows("a,\"b, c\",\"say \"\"hi\"\"\"\n\"two\nlines\",x\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["two\nlines", "x"]])
    }
}
