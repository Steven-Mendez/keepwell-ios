import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// Merchants in storage, on the wire and in backups: `merchant` rows, the optional-and-nullable
/// `merchant_id` / `via_merchant_id` links (a row without the key keeps what is stored; null clears),
/// backup version 3, and a V14 store opening with V15.
@Suite("Merchants in storage")
struct MerchantPersistenceTests {
    private let sample = SampleData.standard
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let subwayID = UUID(uuidString: "66666666-6666-4666-8666-666666666666") ?? UUID()
    private let uberEatsID = UUID(uuidString: "77777777-7777-4777-8777-777777777777") ?? UUID()
    private let movementID = UUID(uuidString: "44444444-4444-4444-8444-444444444444") ?? UUID()

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    private var subway: Merchant {
        Merchant(id: subwayID, name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    }

    private var uberEats: Merchant {
        Merchant(id: uberEatsID, name: "Uber Eats", domain: "ubereats.com", isPlatform: true)
    }

    private func movement(merchantID: UUID?, viaMerchantID: UUID?) throws -> Transaction {
        try Transaction(
            id: movementID, date: now, description: "Subway", kind: .expense, categoryID: "restaurants", amount: 12,
            currency: "USD", accountID: #require(sample.accounts.first?.id), exchangeRate: sample.settings.currencies.exchangeRate,
            merchantID: merchantID, viaMerchantID: viaMerchantID,
        )
    }

    // MARK: Shared fixture (sync.json)

    private func syncFixture() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "sync", withExtension: "json", subdirectory: "Fixtures"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private struct Event {
        let name: String
        let entity: String
        let id: String
        let payload: [String: Any]
    }

    private func events(_ key: String) throws -> [Event] {
        let list = try #require(syncFixture()[key] as? [[String: Any]])
        return try list.map { item in
            let event = try #require(item["event"] as? [String: Any])
            return try Event(
                name: #require(item["name"] as? String),
                entity: #require(event["entity"] as? String),
                id: #require(event["entity_id"] as? String),
                payload: #require(event["payload"] as? [String: Any]),
            )
        }
    }

    private func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Every merchant row and every row with merchant links reads, and goes back out with the same
    /// columns.
    @Test
    func readsAndWritesBackTheFixtureRowsWithMerchants() async throws {
        let merchantRows = try events("valid").filter { event in
            event.entity == "merchant" || event.payload.keys.contains("merchant_id")
        }
        #expect(merchantRows.count == 5)
        for item in merchantRows {
            let store = try store()
            #expect(try await store.applyRemote(entity: item.entity, row: JSONSerialization.data(withJSONObject: item.payload)))
            try await store.queueFullUpload(replacing: [], at: .now)
            let event = try await store.pendingEvents(limit: 1000).first { $0.entity == item.entity && $0.entityID == item.id }
            let written = try row(#require(event, "\(item.name) isn't written back"))
            for (column, value) in item.payload where column != "imported_id" {
                let back = try #require(written[column], "\(item.name): \(column) is lost")
                #expect(try json(back) == json(value), "\(item.name): \(column)")
            }
        }
    }

    @Test
    func refusesTheFixtureRowsWithBadMerchants() async throws {
        let bad = try events("invalid").filter { $0.name.contains("merchant") }
        #expect(bad.count == 4)
        for item in bad {
            let store = try store()
            await #expect(throws: DomainError.self, "\(item.name)") {
                try await store.applyRemote(entity: item.entity, row: JSONSerialization.data(withJSONObject: item.payload))
            }
            #expect(BackupColumns.problem(entity: item.entity, row: item.payload) != nil || item.name == "merchant with a blank name")
        }
    }

    // MARK: Wire

    @Test
    func movementsAlwaysSendBothLinksWithNullForNone() async throws {
        let phone = try store()
        try await phone.save(subway)
        try await phone.save(uberEats)
        let merchantRow = try row(#require(try await phone.pendingEvents().first { $0.entity == "merchant" }))
        #expect(merchantRow["name"] as? String == "Subway")
        #expect(merchantRow["brand_id"] as? String == "subway")
        #expect(merchantRow["is_platform"] as? Bool == false)

        try await phone.save(movement(merchantID: subwayID, viaMerchantID: uberEatsID))
        let linked = try row(#require(try await phone.pendingEvents().last))
        #expect(linked["merchant_id"] as? String == subwayID.uuidString.lowercased())
        #expect(linked["via_merchant_id"] as? String == uberEatsID.uuidString.lowercased())

        try await phone.save(movement(merchantID: nil, viaMerchantID: nil))
        let cleared = try row(#require(try await phone.pendingEvents().last))
        #expect(cleared["merchant_id"] is NSNull)
        #expect(cleared["via_merchant_id"] is NSNull)
    }

    @Test
    func categorizationRulesSendTheirMerchant() async throws {
        let phone = try store()
        try await phone.save(CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense, merchantID: subwayID))
        let sent = try row(#require(try await phone.pendingEvents().last))
        #expect(sent["merchant_id"] as? String == subwayID.uuidString.lowercased())
        #expect(try await phone.fetchCategorizationRules().first?.merchantID == subwayID)
    }

    /// An app older than merchants sends rows without the keys: the links stay. Null clears them.
    @Test
    func aRowWithoutTheKeysKeepsTheLinksAndNullClearsThem() async throws {
        let phone = try store()
        try await phone.save(movement(merchantID: subwayID, viaMerchantID: uberEatsID))
        var old = try row(#require(try await phone.pendingEvents().last))
        old.removeValue(forKey: "merchant_id")
        old.removeValue(forKey: "via_merchant_id")
        old["description"] = "Subway centro"
        old["updated_at"] = "2030-01-01T00:00:00.000Z"
        #expect(try await phone.applyRemote(entity: "transaction", row: JSONSerialization.data(withJSONObject: old)))
        let kept = try #require(try await phone.fetchTransactions(in: nil).first)
        #expect(kept.description == "Subway centro")
        #expect(kept.merchantID == subwayID)
        #expect(kept.viaMerchantID == uberEatsID)

        old["via_merchant_id"] = NSNull()
        old["updated_at"] = "2030-01-02T00:00:00.000Z"
        try await phone.applyRemote(entity: "transaction", row: JSONSerialization.data(withJSONObject: old))
        let cleared = try #require(try await phone.fetchTransactions(in: nil).first)
        #expect(cleared.merchantID == subwayID)
        #expect(cleared.viaMerchantID == nil)
        #expect(BackupColumns.problem(entity: "transaction", row: old) == nil)
    }

    // MARK: Repository

    @Test
    func commitIsAllOrNothing() async throws {
        let phone = try store()
        try await phone.save(subway)
        try await phone.save(movement(merchantID: subwayID, viaMerchantID: nil))
        let unlinked = try movement(merchantID: nil, viaMerchantID: nil)
        await #expect(throws: DomainError.notFound(uberEatsID)) {
            try await phone.commit(MerchantChanges(transactions: [unlinked], deletedMerchantIDs: [subwayID, uberEatsID]))
        }
        #expect(try await phone.fetchTransactions(in: nil).first?.merchantID == subwayID)
        #expect(try await phone.fetchMerchants().count == 1)

        try await phone.commit(MerchantChanges(transactions: [unlinked], deletedMerchantIDs: [subwayID]))
        #expect(try await phone.fetchTransactions(in: nil).first?.merchantID == nil)
        #expect(try await phone.fetchMerchants().isEmpty)
        #expect(try await phone.deletedMerchantIDs() == [subwayID])
        #expect(try await phone.localRowCounts()["merchant"] == 0)
    }
}

extension MerchantPersistenceTests {
    // MARK: Backup

    @Test
    func backupVersionThreeKeepsMerchantsAndLinks() async throws {
        let source = try store()
        try await source.save(sample.settings)
        try await source.save(sample.accounts[0])
        try await source.save(subway)
        try await source.save(uberEats)
        try await source.save(movement(merchantID: subwayID, viaMerchantID: uberEatsID))
        let backup = try await source.exportBackup(at: now)
        let file = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        #expect(file["version"] as? Int == 3)
        #expect((file["entities"] as? [String: [Any]])?["merchant"]?.count == 2)

        let restored = try store()
        try await restored.importBackup(backup, at: now)
        #expect(try await Set(restored.fetchMerchants()) == [subway, uberEats])
        let back = try #require(try await restored.fetchTransactions(in: nil).first)
        #expect(back.merchantID == subwayID)
        #expect(back.viaMerchantID == uberEatsID)
    }

    /// A version 2 file (no merchants, movements without the link keys) still restores.
    @Test
    func readsAVersionTwoBackup() async throws {
        let source = try store()
        try await source.save(sample.settings)
        try await source.save(sample.accounts[0])
        try await source.save(movement(merchantID: nil, viaMerchantID: nil))
        let exported = try await source.exportBackup(at: now)
        var file = try #require(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        var entities = try #require(file["entities"] as? [String: [[String: Any]]])
        entities.removeValue(forKey: "merchant")
        entities["transaction"] = entities["transaction"]?.map { row in
            row.filter { $0.key != "merchant_id" && $0.key != "via_merchant_id" }
        }
        entities["categorizationRule"] = []
        file["entities"] = entities
        file["version"] = 2

        let restored = try store()
        try await restored.importBackup(JSONSerialization.data(withJSONObject: file), at: now)
        let back = try #require(try await restored.fetchTransactions(in: nil).first)
        #expect(back.id == movementID)
        #expect(back.merchantID == nil)
        #expect(try await restored.fetchMerchants().isEmpty)
    }

    @Test
    func refusesABackupWithABadMerchant() async throws {
        let file: [String: Any] = [
            "format": "keepwell-backup", "version": 3, "exported_at": "2026-11-12T00:00:00.000Z",
            "entities": ["merchant": [[
                "id": subwayID.uuidString.lowercased(), "name": "Subway", "domain": "https://subway.com", "brand_id": NSNull(),
                "default_category_id": NSNull(), "is_platform": false, "created_at": "2026-11-01T18:00:00.000Z",
                "updated_at": "2026-11-01T18:00:00.000Z", "deleted_at": NSNull(),
            ]]],
        ]
        let restored = try store()
        await #expect(throws: BackupRestoreError.invalid("merchant[0]: domain")) {
            try await restored.importBackup(JSONSerialization.data(withJSONObject: file), at: now)
        }
    }

    // MARK: Migration

    /// A store written by V14 opens with V15: movements, recurring rules and categorization rules
    /// keep everything and start naming no merchant.
    @Test
    func versionFourteenStoreMigratesToVersionFifteen() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")
        let ruleID = UUID()

        try writeVersionFourteenStore(at: url, ruleID: ruleID)

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let store = SwiftDataStore(modelContainer: container)
        let movement = try #require(try await store.fetchTransactions(in: nil).first)
        #expect(movement.id == movementID)
        #expect(movement.description == "Subway")
        #expect(movement.amount == 12)
        #expect(movement.merchantID == nil)
        #expect(movement.viaMerchantID == nil)
        let rule = try #require(try await store.fetchCategorizationRules().first)
        #expect(rule.id == ruleID)
        #expect(rule.merchantID == nil)
        #expect(try await store.fetchRecurringRules().first?.merchantID == nil)
        #expect(try await store.fetchMerchants().isEmpty)
        try await store.save(subway)
        #expect(try await store.fetchMerchants() == [subway])
    }

    private func writeVersionFourteenStore(at url: URL, ruleID: UUID) throws {
        let schema = Schema(versionedSchema: KeepwellSchemaV14.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let context = ModelContext(container)
        let record = KeepwellSchemaV14.TransactionRecord()
        record.id = movementID
        record.descriptionText = "Subway"
        record.categoryID = "restaurants"
        record.amount = "12"
        record.currency = "USD"
        record.ratePrincipal = "USD"
        record.rateSecond = "NIO"
        record.rate = "36.6243"
        record.date = now
        context.insert(record)
        let rule = KeepwellSchemaV14.CategorizationRuleRecord()
        rule.id = ruleID
        rule.match = "Subway"
        rule.categoryID = "restaurants"
        context.insert(rule)
        context.insert(KeepwellSchemaV14.RecurringRuleRecord())
        try context.save()
    }
}
