import Domain
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// A closed account's `closed_at` on the wire (T25, receta paso 4): always sent, null while open; a
/// row without the key, from an app older than the column, leaves the closing alone; a key this app
/// doesn't know yet is ignored without failing. And a V13 store opens with V14.
@Suite("Account closing on the wire")
struct AccountClosedAtWireTests {
    private let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID()
    private let closedAt = Date(timeIntervalSince1970: 1_793_525_400) // 2026-11-01T09:30:00Z

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    private func account(closedAt: Date?) -> Account {
        Account(id: id, name: "Ahorro", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .distantPast, closedAt: closedAt)
    }

    /// The row as an app older than the column builds it: no `closed_at` key at all.
    private func oldRow(updatedAt: String, name: String = "Ahorro") -> [String: Any] {
        [
            "id": id.uuidString.lowercased(), "name": name, "bank": NSNull(), "kind": "deposit",
            "opening_balances": [["amount": "0", "currency": "USD"]], "opening_date": "2026-01-01T12:00:00.000Z",
            "debt_mode": NSNull(), "limit_amount": NSNull(), "limit_currency": NSNull(), "cutoff_day": NSNull(), "due_day": NSNull(),
            "created_at": "2026-11-01T18:00:00.000Z", "updated_at": updatedAt, "deleted_at": NSNull(),
        ]
    }

    @Test
    func isAlwaysSentAndNullWhileOpen() async throws {
        let phone = try store()
        try await phone.save(account(closedAt: closedAt))
        let closed = try row(#require(try await phone.pendingEvents().last))
        #expect(closed["closed_at"] as? String == "2026-11-01T09:30:00.000Z")
        try await phone.save(account(closedAt: nil))
        let reopened = try row(#require(try await phone.pendingEvents().last))
        #expect(reopened["closed_at"] is NSNull)
    }

    @Test
    func aRowWithoutTheColumnKeepsTheClosingAndNullReopens() async throws {
        let phone = try store()
        var pulled = oldRow(updatedAt: "2030-01-01T00:00:00.000Z")
        pulled["closed_at"] = "2026-11-01T09:30:00.000Z"
        _ = try await phone.applyRemote(entity: "account", row: JSONSerialization.data(withJSONObject: pulled))
        #expect(try await phone.fetchAccounts().first?.closedAt == closedAt)

        let renamed = oldRow(updatedAt: "2030-01-02T00:00:00.000Z", name: "Ahorro viejo")
        _ = try await phone.applyRemote(entity: "account", row: JSONSerialization.data(withJSONObject: renamed))
        let kept = try #require(try await phone.fetchAccounts().first)
        #expect(kept.name == "Ahorro viejo")
        #expect(kept.closedAt == closedAt)

        var reopened = oldRow(updatedAt: "2030-01-03T00:00:00.000Z")
        reopened["closed_at"] = NSNull()
        _ = try await phone.applyRemote(entity: "account", row: JSONSerialization.data(withJSONObject: reopened))
        #expect(try await phone.fetchAccounts().first?.closedAt == nil)
    }

    @Test
    func aColumnThisAppDoesntKnowYetIsIgnored() async throws {
        let phone = try store()
        var pulled = oldRow(updatedAt: "2030-01-01T00:00:00.000Z")
        pulled["closed_at"] = "2026-11-01T09:30:00.000Z"
        pulled["a_later_column"] = "x"
        #expect(try await phone.applyRemote(entity: "account", row: JSONSerialization.data(withJSONObject: pulled)))
        #expect(try await phone.fetchAccounts().first?.closedAt == closedAt)
        #expect(BackupColumns.problem(entity: "account", row: pulled) == nil)
        pulled.removeValue(forKey: "closed_at")
        #expect(BackupColumns.problem(entity: "account", row: pulled) == nil)
    }

    /// A store written by V13 opens with V14: its accounts keep everything and start open.
    @Test
    func versionThirteenStoreMigratesToVersionFourteen() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV13.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            let record = KeepwellSchemaV13.AccountRecord()
            record.id = id
            record.name = "Ahorro"
            record.openingBalances = "USD:250"
            record.openingDate = closedAt
            context.insert(record)
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let account = try #require(try await SwiftDataStore(modelContainer: container).fetchAccounts().first)
        #expect(account.id == id)
        #expect(account.name == "Ahorro")
        #expect(account.openingBalances == [Money(250, "USD")])
        #expect(account.closedAt == nil)
    }
}
