import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Backup of recurring rules")
struct RecurringBackupTests {
    private let sample = SampleData.standard
    private let stamp = RecordMetadata(
        createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_793_000_000.5),
    )

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// One rule and the movement it recorded, with fixed values, so the exact text both apps write
    /// is pinned here.
    private func fixedContents() throws -> BackupContents {
        let ruleID = try #require(UUID(uuidString: "6F1C2B0A-3D4E-4F5A-8B9C-0D1E2F3A4B5C"))
        let rule = RecurringRule(
            id: ruleID,
            name: "Streaming",
            kind: .expense,
            categoryID: "subscriptions",
            amount: Decimal(string: "15.99") ?? 0,
            currency: "USD",
            accountID: SampleData.IDs.mastercard,
            cardID: SampleData.IDs.mastercardHolder,
            frequency: .monthly,
            interval: 1,
            startDate: Date(timeIntervalSince1970: 1_790_000_000),
            nextDate: Date(timeIntervalSince1970: 1_792_678_400),
            isSubscription: true,
            autoConfirm: false,
        )
        let movement = try RecurringSchedule.movement(
            from: rule,
            on: rule.startDate,
            exchangeRate: sample.settings.currencies.exchangeRate,
            id: #require(UUID(uuidString: "0A0B0C0D-0E0F-4011-8213-141516171819")),
        )
        let contents = InMemoryStoreSnapshot.contents(of: sample)
        return BackupContents(
            settings: contents.settings,
            accounts: contents.accounts,
            cards: contents.cards,
            categories: contents.categories,
            transactions: [Stamped(movement, stamp)],
            recurringRules: [Stamped(rule, stamp)],
        )
    }

    @Test
    func aRuleIsWrittenWithTheSharedKeysAndTheMovementNamesIt() throws {
        let data = try #require(BackupSnapshot(contents: fixedContents(), exportedAt: stamp.createdAt)).encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        // The same text the web app writes: keys sorted, empty optionals left out, exact decimals.
        let rule = """
        {"accountId":"00000000-0000-0000-0000-00000000a004","amount":"15.99","autoConfirm":false,\
        "cardId":"00000000-0000-0000-0000-00000000c005","categoryId":"subscriptions",\
        "createdAt":"2026-10-26T07:33:20.000Z","currency":"USD","frequency":"monthly",\
        "id":"6f1c2b0a-3d4e-4f5a-8b9c-0d1e2f3a4b5c","interval":1,"isPaused":false,"isSubscription":true,\
        "kind":"expense","name":"Streaming","nextDate":"2026-10-22T14:13:20.000Z",\
        "startDate":"2026-09-21T14:13:20.000Z","updatedAt":"2026-10-26T07:33:20.500Z"}
        """
        #expect(text.contains("\"recurringRules\":[\(rule)]"))
        #expect(text.contains("\"recurringId\":\"6f1c2b0a-3d4e-4f5a-8b9c-0d1e2f3a4b5c\""))
        #expect(try json(data)["schemaVersion"] as? Int == 2)
    }

    @Test
    func rulesAndTheMovementsTheyRecordedRoundTrip() async throws {
        let contents = try fixedContents()
        let data = try #require(BackupSnapshot(contents: contents, exportedAt: .now)).encoded()
        let store = InMemoryStore()
        _ = try await DefaultRestoreBackupUseCase(store: store).execute(data)
        #expect(await store.fetchRecurringRules() == contents.recurringRules.map(\.value))
        let movement = try #require(await store.fetchTransactions(in: nil).first)
        #expect(movement.recurringID == contents.recurringRules.first?.value.id)
    }

    @Test
    func aVersionOneFileStillRestoresWithNoRules() async throws {
        let data = try #require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded()
        var file = try json(data)
        file["schemaVersion"] = 1
        file.removeValue(forKey: "recurringRules")
        var transactions = try #require(file["transactions"] as? [[String: Any]])
        transactions = transactions.map { row in
            var row = row
            row.removeValue(forKey: "recurringId")
            return row
        }
        file["transactions"] = transactions

        let store = InMemoryStore(sample: sample)
        let summary = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        #expect(summary.transactions == 1)
        #expect(await store.fetchRecurringRules().isEmpty)
        #expect(await store.fetchTransactions(in: nil).first?.recurringID == nil)
    }

    @Test
    func aRuleWithAnIntervalOutOfRangeIsRefused() async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        var rules = try #require(file["recurringRules"] as? [[String: Any]])
        rules[0]["interval"] = 0
        file["recurringRules"] = rules
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.invalidInterval(0)) {
            _ = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        }
        #expect(await store.fetchRecurringRules() == sample.recurringRules)
    }
}

/// The sample as a store would export it, stamped with a fixed time.
private enum InMemoryStoreSnapshot {
    static func contents(of sample: SampleData) -> BackupContents {
        let stamp = RecordMetadata(
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
        )
        return BackupContents(
            settings: Stamped(sample.settings, stamp),
            accounts: sample.accounts.map { Stamped($0, stamp) },
            cards: sample.cards.map { Stamped($0, stamp) },
            categories: sample.categories.map { Stamped($0, stamp) },
            transactions: [],
        )
    }
}
