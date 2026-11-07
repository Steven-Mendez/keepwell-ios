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

extension ImportTransactionsTests {
    @Test
    func rowsWithoutAKnownCategoryTakeTheFirstMatchingRule() async throws {
        let store = InMemoryStore(sample: sample)
        let cash = try #require(sample.accounts.first { $0.id == SampleData.IDs.cash })
        await store.save(CategorizationRule(match: "taxi", categoryID: "transport", kind: .expense, tags: ["trabajo"]))
        let csv = """
        date,type,description,category,amount,currency,account,note
        2026-10-03,expense,TAXÍ *TRIP,,120,NIO,\(cash.name),
        2026-10-03,expense,Ride home,,80,NIO,\(cash.name),taxi to the airport
        2026-10-03,expense,Taxi gift,Gifts,90,NIO,\(cash.name),
        2026-10-03,expense,Corner bakery,,30,NIO,\(cash.name),
        """
        let importer = DefaultImportTransactionsUseCase(
            transactions: store, accounts: store, cards: store, categories: store, settings: store, rules: store,
        )
        #expect(try await importer.execute(csv: csv).imported == 4)
        let saved = await store.fetchTransactions(in: nil)
        func movement(_ description: String) throws -> Transaction {
            try #require(saved.first { $0.description == description })
        }
        #expect(try movement("TAXÍ *TRIP").categoryID == "transport")
        #expect(try movement("TAXÍ *TRIP").tags == ["trabajo"])
        #expect(try movement("Ride home").categoryID == "transport")
        #expect(try movement("Taxi gift").categoryID == "gifts")
        #expect(try movement("Taxi gift").tags.isEmpty)
        #expect(try movement("Corner bakery").categoryID == TransactionCategory.otherExpenseID)
    }
}

extension ImportTransactionsTests {
    @Test
    func tagsGoOutAsTheLastColumnAndComeBack() async throws {
        let cash = try #require(sample.accounts.first { $0.id == SampleData.IDs.cash })
        let tagged = Transaction(
            date: SampleData.defaultReferenceDate, description: "Hotel", kind: .expense, categoryID: "travel",
            amount: 900, currency: "NIO", accountID: cash.id, exchangeRate: .single("NIO"), tags: ["viaje-mexico", "boda"],
        )
        let csv = DefaultExportTransactionsUseCase.csv(
            transactions: [tagged],
            accounts: sample.accounts,
            cards: [],
            categories: TransactionCategory.defaults,
        )
        let rows = CSV.rows(csv)
        #expect(rows.first?.last == "tags")
        #expect(rows.last?.last == "#viaje-mexico #boda")

        let store = InMemoryStore(sample: sample)
        #expect(try await importer(store).execute(csv: csv).imported == 1)
        let saved = try #require(await store.fetchTransactions(in: nil).first { $0.description == "Hotel" })
        #expect(saved.tags == ["viaje-mexico", "boda"])
    }

    @Test
    func importedTagsAreSplitOnSpacesOrCommasAndNormalized() async throws {
        let store = InMemoryStore(sample: sample)
        let cash = try #require(sample.accounts.first { $0.id == SampleData.IDs.cash })
        await store.save(CategorizationRule(match: "taxi", categoryID: "transport", kind: .expense, tags: ["trabajo"]))
        let csv = """
        date,type,description,category,amount,currency,account,Tags
        2026-10-04,expense,Flowers,Gifts,50,NIO,\(cash.name),"#Boda, Viaje  #boda"
        2026-10-04,expense,Taxi,,70,NIO,\(cash.name),#viaje
        """
        let importer = DefaultImportTransactionsUseCase(
            transactions: store, accounts: store, cards: store, categories: store, settings: store, rules: store,
        )
        #expect(try await importer.execute(csv: csv).imported == 2)
        let saved = await store.fetchTransactions(in: nil)
        #expect(saved.first { $0.description == "Flowers" }?.tags == ["boda", "viaje"])
        // The file's tags first, then the rule's.
        #expect(saved.first { $0.description == "Taxi" }?.tags == ["viaje", "trabajo"])
    }
}
