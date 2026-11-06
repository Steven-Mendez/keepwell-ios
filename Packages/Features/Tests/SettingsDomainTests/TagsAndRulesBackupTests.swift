import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Backup of tags and categorization rules")
struct TagsAndRulesBackupTests {
    private let sample = SampleData.standard
    private let stamp = RecordMetadata(
        createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_793_000_000.5),
    )

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func id(_ text: String) throws -> UUID {
        try #require(UUID(uuidString: text))
    }

    /// A tagged movement and two rules with fixed values, so the exact text both apps write is
    /// pinned here and in the web's `categorization.test.ts`.
    private func fixedContents() throws -> BackupContents {
        let movement = try Transaction(
            id: id("7D8E9FA0-B1C2-4D3E-8F40-5162738495A6"),
            date: Date.ISO8601FormatStyle().parse("2026-11-14T18:00:00Z"),
            description: "Uber to the airport",
            kind: .expense,
            categoryID: "transport",
            amount: Decimal(string: "12.5") ?? 0,
            currency: "USD",
            accountID: SampleData.IDs.savings,
            exchangeRate: sample.settings.currencies.exchangeRate,
            tags: ["#Viaje México", "boda", "viaje méxico"],
        )
        let uber = try CategorizationRule(
            id: id("8E9FA0B1-C2D3-4E4F-9051-62738495A6B7"),
            match: "Uber",
            categoryID: "transport",
            kind: .expense,
            tags: ["Viaje México"],
        )
        let payroll = try CategorizationRule(
            id: id("9FA0B1C2-D3E4-4F50-A162-738495A6B7C8"),
            match: "Payroll",
            categoryID: "salary",
            kind: .income,
        )
        let deleted = RecordMetadata(createdAt: stamp.createdAt, updatedAt: stamp.updatedAt, deletedAt: stamp.updatedAt)
        return BackupContents(
            settings: Stamped(sample.settings, stamp),
            accounts: sample.accounts.map { Stamped($0, stamp) },
            cards: sample.cards.map { Stamped($0, stamp) },
            categories: sample.categories.map { Stamped($0, stamp) },
            transactions: [Stamped(movement, stamp)],
            categorizationRules: [Stamped(uber, stamp), Stamped(payroll, deleted)],
        )
    }

    @Test
    func tagsAndRulesAreWrittenWithTheSharedKeysInSchemaFour() throws {
        let data = try #require(BackupSnapshot(contents: fixedContents(), exportedAt: stamp.createdAt)).encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        // The same text the web app writes: keys sorted, empty optionals left out.
        let transaction = """
        "transactions":[{"accountId":"00000000-0000-0000-0000-00000000a001","amount":"12.5","categoryId":"transport",\
        "createdAt":"2026-10-26T07:33:20.000Z","currency":"USD","date":"2026-11-14T18:00:00.000Z",\
        "description":"Uber to the airport","exchangeRate":{"principal":"USD","rate":"36.6243","second":"NIO"},\
        "id":"7d8e9fa0-b1c2-4d3e-8f40-5162738495a6","isShared":false,"kind":"expense","status":"confirmed",\
        "tags":["viaje-méxico","boda"],"updatedAt":"2026-10-26T07:33:20.500Z"}]
        """
        let rules = """
        "categorizationRules":[{"categoryId":"transport","createdAt":"2026-10-26T07:33:20.000Z",\
        "id":"8e9fa0b1-c2d3-4e4f-9051-62738495a6b7","kind":"expense","match":"Uber","sortIndex":0,\
        "tags":["viaje-méxico"],"updatedAt":"2026-10-26T07:33:20.500Z"},\
        {"categoryId":"salary","createdAt":"2026-10-26T07:33:20.000Z","deletedAt":"2026-10-26T07:33:20.500Z",\
        "id":"9fa0b1c2-d3e4-4f50-a162-738495a6b7c8","kind":"income","match":"Payroll","sortIndex":1,\
        "updatedAt":"2026-10-26T07:33:20.500Z"}]
        """
        #expect(text.contains(transaction))
        #expect(text.contains(rules))
        #expect(try json(data)["schemaVersion"] as? Int == 4)
    }

    @Test
    func tagsAndRulesRoundTripWithTheirOrderAndDeletions() async throws {
        let contents = try fixedContents()
        let data = try #require(BackupSnapshot(contents: contents, exportedAt: .now)).encoded()
        let decoded = try BackupSnapshot.decode(data).contents()
        #expect(decoded.transactions == contents.transactions)
        #expect(decoded.categorizationRules == contents.categorizationRules)

        let store = InMemoryStore()
        _ = try await DefaultRestoreBackupUseCase(store: store).execute(data)
        #expect(await store.fetchTransactions(in: nil).first?.tags == ["viaje-méxico", "boda"])
        #expect(await store.fetchCategorizationRules() == [contents.categorizationRules[0].value])
    }

    @Test
    func aFileWithoutTagsOrRulesStillRestores() async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        file.removeValue(forKey: "categorizationRules")
        var transactions = try #require(file["transactions"] as? [[String: Any]])
        transactions[0].removeValue(forKey: "tags")
        file["transactions"] = transactions
        let store = InMemoryStore(sample: sample)
        _ = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        #expect(await store.fetchTransactions(in: nil).first?.tags.isEmpty == true)
        #expect(await store.fetchCategorizationRules().isEmpty)
    }

    @Test
    func aRuleForTransfersIsRefused() async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        var rules = try #require(file["categorizationRules"] as? [[String: Any]])
        rules[0]["kind"] = "transfer"
        file["categorizationRules"] = rules
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.self) {
            _ = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        }
        #expect(await store.fetchCategorizationRules() == sample.categorizationRules)
    }
}
