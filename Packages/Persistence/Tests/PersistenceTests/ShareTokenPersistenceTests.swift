import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// A split expense's public link in storage and on the wire: `share_token` is always sent (null when
/// not shared), a row without the key keeps the stored one, null clears it, and a V15 store opens with
/// V16.
@Suite("Shared split links in storage")
struct ShareTokenPersistenceTests {
    private let sample = SampleData.standard
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let movementID = UUID(uuidString: "44444444-4444-4444-8444-444444444444") ?? UUID()
    private let token = "AbCdEfGhIjKlMnOpQrSt_-"

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    private func dinner(shareToken: String?) throws -> Transaction {
        try Transaction(
            id: movementID, date: now, description: "Los Taki Pollos", kind: .expense, categoryID: "restaurants", amount: 1156.25,
            currency: "NIO", accountID: #require(sample.accounts.first?.id), exchangeRate: sample.settings.currencies.exchangeRate,
            shareToken: shareToken,
        )
    }

    @Test
    func aMovementSendsItsLinkAndNullOnceSharingStops() async throws {
        let phone = try store()
        try await phone.save(dinner(shareToken: token))
        #expect(try row(#require(try await phone.pendingEvents().last))["share_token"] as? String == token)
        #expect(try await phone.fetchTransactions(in: nil).first?.shareToken == token)
        try await phone.save(dinner(shareToken: nil))
        #expect(try row(#require(try await phone.pendingEvents().last))["share_token"] is NSNull)
    }

    /// An app older than shared links sends rows without the key: the link stays. Null clears it.
    @Test
    func aRowWithoutTheKeyKeepsTheLinkAndNullClearsIt() async throws {
        let phone = try store()
        try await phone.save(dinner(shareToken: token))
        var old = try row(#require(try await phone.pendingEvents().last))
        old.removeValue(forKey: "share_token")
        old["description"] = "Taki Pollos"
        old["updated_at"] = "2030-01-01T00:00:00.000Z"
        #expect(try await phone.applyRemote(entity: "transaction", row: JSONSerialization.data(withJSONObject: old)))
        let kept = try #require(try await phone.fetchTransactions(in: nil).first)
        #expect(kept.description == "Taki Pollos")
        #expect(kept.shareToken == token)

        old["share_token"] = NSNull()
        old["updated_at"] = "2030-01-02T00:00:00.000Z"
        try await phone.applyRemote(entity: "transaction", row: JSONSerialization.data(withJSONObject: old))
        #expect(try await phone.fetchTransactions(in: nil).first?.shareToken == nil)
        #expect(BackupColumns.problem(entity: "transaction", row: old) == nil)
    }

    @Test
    func versionFifteenStoreMigratesToVersionSixteen() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        let old = Schema(versionedSchema: KeepwellSchemaV15.self)
        let oldContainer = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url, cloudKitDatabase: .none))
        let context = ModelContext(oldContainer)
        let record = KeepwellSchemaV15.TransactionRecord()
        record.id = movementID
        record.descriptionText = "Los Taki Pollos"
        record.categoryID = "restaurants"
        record.amount = "1156.25"
        record.currency = "NIO"
        record.ratePrincipal = "USD"
        record.rateSecond = "NIO"
        record.rate = "36.6243"
        record.date = now
        context.insert(record)
        try context.save()

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let movement = try #require(try await SwiftDataStore(modelContainer: container).fetchTransactions(in: nil).first)
        #expect(movement.id == movementID)
        #expect(movement.amount == Decimal(string: "1156.25"))
        #expect(movement.shareToken == nil)
    }
}
