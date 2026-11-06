import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Backup and restore")
struct BackupTests {
    private let sample = SampleData.standard

    private func create(_ store: InMemoryStore) async throws -> Data {
        try await DefaultCreateBackupUseCase(store: store).execute()
    }

    private func restore(_ data: Data, into store: InMemoryStore) async throws -> RestoreSummary {
        try await DefaultRestoreBackupUseCase(store: store).execute(data)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The file written by an app before `schemaVersion`, as people may still keep it.
    private func legacyBackup(categories: [TransactionCategory]? = nil) throws -> Data {
        let document = BackupDocument(
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            settings: sample.settings,
            accounts: sample.accounts,
            cards: sample.cards,
            categories: categories ?? sample.categories,
            transactions: sample.transactions,
        )
        return try BackupDocument.encoder.encode(document)
    }

    @Test
    func aBackupRestoresEverythingAsItWas() async throws {
        let original = InMemoryStore(sample: sample)
        let backup = try await create(original)

        let other = InMemoryStore(sample: sample)
        for transaction in sample.transactions.prefix(3) {
            try await other.deleteTransaction(id: transaction.id)
        }
        let summary = try await restore(backup, into: other)

        #expect(summary.transactions == sample.transactions.count)
        #expect(summary.accounts == sample.accounts.count)
        #expect(await Set(other.fetchTransactions(in: nil)) == Set(sample.transactions))
        #expect(await Set(other.fetchCards()) == Set(sample.cards))
        #expect(await other.load()?.currencies == sample.settings.currencies)
    }

    /// The web app reads the file with `JSON.parse`, which turns every number into a binary double.
    @Test
    func theFileIsVersionedAndKeepsAmountsAsExactText() async throws {
        let backup = try await json(create(InMemoryStore(sample: sample)))
        #expect(backup["schemaVersion"] as? Int == BackupSnapshot.currentSchemaVersion)

        let transactions = try #require(backup["transactions"] as? [[String: Any]])
        #expect(transactions.count == sample.transactions.count)
        for (row, transaction) in zip(transactions, sample.transactions) {
            #expect(row["amount"] as? String == transaction.amount.description)
            #expect(row["id"] as? String == transaction.id.uuidString.lowercased())
            #expect((row["exchangeRate"] as? [String: Any])?["rate"] is String)
        }
        let settings = try #require(backup["settings"] as? [String: Any])
        #expect((settings["currencies"] as? [String: Any])?["rate"] is String)
    }

    /// Budgets travel like every other amount: exact text with its currency, and no key without one.
    @Test
    func aMonthlyBudgetRoundTripsAsExactTextAndIsLeftOutWhenNone() async throws {
        let budget = Money(Decimal(string: "1250.05") ?? 0, "USD")
        let categories = sample.categories.map { category in
            guard category.id == "groceries" else { return category }
            return TransactionCategory(
                id: category.id, name: category.name, kind: category.kind, icon: category.icon, color: category.color,
                isRenamed: category.isRenamed, monthlyBudget: budget,
            )
        }
        let original = InMemoryStore(
            accounts: sample.accounts, cards: sample.cards, transactions: sample.transactions,
            categories: categories, settings: sample.settings, recurringRules: sample.recurringRules,
        )
        let backup = try await create(original)

        let rows = try #require(json(backup)["categories"] as? [[String: Any]])
        let groceries = try #require(rows.first { $0["id"] as? String == "groceries" })
        let encoded = try #require(groceries["monthlyBudget"] as? [String: Any])
        #expect(encoded["amount"] as? String == "1250.05")
        #expect(encoded["currency"] as? String == "USD")
        #expect(rows.filter { $0["id"] as? String != "groceries" }.allSatisfy { $0["monthlyBudget"] == nil })

        let restored = InMemoryStore()
        _ = try await restore(backup, into: restored)
        let back = await restored.fetchCategories()
        #expect(back.first { $0.id == "groceries" }?.monthlyBudget == budget)
        #expect(back.filter { $0.id != "groceries" }.allSatisfy { $0.monthlyBudget == nil })
    }

    @Test
    func aNonPositiveBudgetInAFileIsRefused() async throws {
        var backup = try await json(create(InMemoryStore(sample: sample)))
        var rows = try #require(backup["categories"] as? [[String: Any]])
        rows[0]["monthlyBudget"] = ["amount": "0", "currency": "USD"]
        backup["categories"] = rows
        await #expect(throws: DomainError.self) {
            _ = try await restore(JSONSerialization.data(withJSONObject: backup), into: InMemoryStore())
        }
    }

    @Test
    func aFileFromTheWebAppWithMillisecondsAndLowercaseIDsRestores() async throws {
        let accountID = UUID()
        let file = """
        {"schemaVersion":1,"exportedAt":"2026-11-05T10:00:00.123Z",
         "settings":{"currencies":{"principal":"USD","second":"NIO","rate":"36.6243"},"unlockMethod":"passcode",
           "relockAfterSeconds":60,"hidesAmountsInAppSwitcher":true,"isICloudBackupEnabled":false,
           "paymentReminderDaysBefore":3,"hasCompletedOnboarding":true,"updatedAt":"2026-11-05T10:00:00.123Z"},
         "accounts":[{"id":"\(accountID.uuidString.lowercased())","name":"BAC","kind":"deposit",
           "openingBalances":[{"amount":"9306.78","currency":"USD"}],"openingDate":"2026-01-01T06:00:00.000Z",
           "createdAt":"2026-11-05T10:00:00.123Z","updatedAt":"2026-11-05T10:00:00.123Z"}],
         "cards":[],"categories":[],
         "transactions":[{"id":"\(UUID().uuidString.lowercased())","date":"2026-11-04T18:30:00.000Z","status":"confirmed",
           "description":"Coffee","kind":"expense","categoryId":"restaurants","amount":"0.10","currency":"USD",
           "accountId":"\(accountID.uuidString.lowercased())","exchangeRate":{"principal":"USD","second":"NIO","rate":"36.6243"},
           "isShared":false,"createdAt":"2026-11-05T10:00:00.123Z","updatedAt":"2026-11-05T10:00:00.123Z",
           "deletedAt":null}]}
        """
        let store = InMemoryStore()
        let summary = try await restore(Data(file.utf8), into: store)

        #expect(summary.transactions == 1)
        let transaction = try #require(await store.fetchTransactions(in: nil).first)
        #expect(transaction.amount == Decimal(string: "0.10"))
        #expect(transaction.exchangeRate.rate == Decimal(string: "36.6243"))
        #expect(await store.fetchAccounts().first?.id == accountID)
    }

    @Test
    func deletedRecordsTravelInTheFileButDontComeBack() async throws {
        let deletedID = try #require(sample.transactions.first?.id)
        let contents = try await InMemoryStore(sample: sample).exportContents()
        let tombstoned = BackupContents(
            settings: contents.settings,
            accounts: contents.accounts,
            cards: contents.cards,
            categories: contents.categories,
            transactions: contents.transactions.map { row in
                guard row.value.id == deletedID else { return row }
                return Stamped(row.value, RecordMetadata(createdAt: row.metadata.createdAt, updatedAt: .now, deletedAt: .now))
            },
        )
        let data = try #require(BackupSnapshot(contents: tombstoned, exportedAt: .now)).encoded()

        let rows = try #require(json(data)["transactions"] as? [[String: Any]])
        #expect(rows.count == sample.transactions.count)
        #expect(rows.first { $0["id"] as? String == deletedID.uuidString.lowercased() }?["deletedAt"] is String)

        let store = InMemoryStore()
        let summary = try await restore(data, into: store)
        #expect(summary.transactions == sample.transactions.count - 1)
        #expect(await !store.fetchTransactions(in: nil).contains { $0.id == deletedID })
    }

    @Test
    func anAmountThatIsntExactDecimalTextIsRefused() async throws {
        var backup = try await json(create(InMemoryStore(sample: sample)))
        var transactions = try #require(backup["transactions"] as? [[String: Any]])
        transactions[0]["amount"] = "12abc"
        backup["transactions"] = transactions
        let store = InMemoryStore(sample: sample)

        await #expect(throws: DomainError.self) {
            _ = try await restore(JSONSerialization.data(withJSONObject: backup), into: store)
        }
        #expect(await store.fetchTransactions(in: nil).count == sample.transactions.count)
    }

    @Test
    func aNewerSchemaIsRefused() async throws {
        var backup = try await json(create(InMemoryStore(sample: sample)))
        backup["schemaVersion"] = BackupSnapshot.currentSchemaVersion + 1
        await #expect(throws: DomainError.self) {
            _ = try await restore(JSONSerialization.data(withJSONObject: backup), into: InMemoryStore())
        }
    }

    @Test
    func aFileThatIsntABackupChangesNothing() async throws {
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.self) {
            _ = try await restore(Data("date,amount\n2026-10-01,3".utf8), into: store)
        }
        #expect(await store.fetchTransactions(in: nil).count == sample.transactions.count)
    }

    @Test
    func anOlderBackupStillRestores() async throws {
        let store = InMemoryStore()
        let summary = try await restore(legacyBackup(), into: store)

        #expect(summary.transactions == sample.transactions.count)
        #expect(await Set(store.fetchTransactions(in: nil)) == Set(sample.transactions))
        #expect(await store.load()?.hasCompletedOnboarding == true)
    }

    @Test
    func aDefaultMissingFromAnOlderBackupStaysDeleted() async throws {
        let kept = sample.categories.filter { $0.id != "pets" }
        let store = InMemoryStore()
        _ = try await restore(legacyBackup(categories: kept), into: store)

        #expect(await !store.fetchCategories().contains { $0.id == "pets" })
    }

    @Test
    func anOlderBackupWithAnAdditionalCardStillRestores() async throws {
        var backup = try json(legacyBackup())
        var cards = try #require(backup["cards"] as? [[String: Any]])
        cards.append([
            "id": UUID().uuidString,
            "accountID": SampleData.IDs.mastercard.uuidString,
            "kind": "creditAdditional",
            "network": "mastercard",
            "lastFour": "8765",
            "color": "lima",
            "additional": ["holderName": "Family", "allowedCategoryIDs": [String](), "alertEachPurchase": true],
            "isPlasticFrozen": false,
        ])
        backup["cards"] = cards
        let older = try JSONSerialization.data(withJSONObject: backup)

        let restored = InMemoryStore(sample: sample)
        _ = try await restore(older, into: restored)

        #expect(await Set(restored.fetchCards()) == Set(sample.cards))
    }
}
