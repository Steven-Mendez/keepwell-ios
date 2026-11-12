import Domain
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// A personal debt's due date on the wire (T24, receta paso 4): always sent, null for none; a row
/// without the key, from an app older than the column, leaves the date alone; a key this app doesn't
/// know yet is ignored without failing. And a V12 store opens with V13.
@Suite("Personal debt due date on the wire")
struct PersonalDebtDueDateWireTests {
    private let id = UUID(uuidString: "55555555-5555-4555-8555-555555555555") ?? UUID()
    private let due = Date(timeIntervalSince1970: 1_794_722_400) // 2026-11-15T06:00:00Z

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    private func debt(due: Date?) -> PersonalDebt {
        PersonalDebt(id: id, person: "Ana", direction: .theyOweMe, amount: Money(12, "USD"), date: .distantPast, dueDate: due)
    }

    /// The row as an app older than the column builds it: no `due_date` key at all.
    private func oldRow(updatedAt: String, note: Any = NSNull()) -> [String: Any] {
        [
            "id": id.uuidString.lowercased(), "person": "Ana", "direction": "theyOweMe", "amount": "12", "currency": "USD",
            "date": "2026-09-01T18:00:00.000Z", "note": note, "settled_at": NSNull(), "transaction_id": NSNull(),
            "created_at": "2026-11-01T18:00:00.000Z", "updated_at": updatedAt, "deleted_at": NSNull(),
        ]
    }

    @Test
    func isAlwaysSentAndNullWithoutOne() async throws {
        let phone = try store()
        try await phone.save(debt(due: due))
        let dated = try row(#require(try await phone.pendingEvents().last))
        #expect(dated["due_date"] as? String == "2026-11-15T06:00:00.000Z")
        try await phone.save(debt(due: nil))
        let cleared = try row(#require(try await phone.pendingEvents().last))
        #expect(cleared["due_date"] is NSNull)
    }

    @Test
    func aRowWithoutTheColumnKeepsTheDateAndNullClearsIt() async throws {
        let phone = try store()
        var pulled = oldRow(updatedAt: "2030-01-01T00:00:00.000Z")
        pulled["due_date"] = "2026-11-15T06:00:00.000Z"
        _ = try await phone.applyRemote(entity: "personalDebt", row: JSONSerialization.data(withJSONObject: pulled))
        #expect(try await phone.fetchPersonalDebts().first?.dueDate == due)

        let old = oldRow(updatedAt: "2030-01-02T00:00:00.000Z", note: "Dinner")
        _ = try await phone.applyRemote(entity: "personalDebt", row: JSONSerialization.data(withJSONObject: old))
        let kept = try #require(try await phone.fetchPersonalDebts().first)
        #expect(kept.note == "Dinner")
        #expect(kept.dueDate == due)

        var cleared = oldRow(updatedAt: "2030-01-03T00:00:00.000Z")
        cleared["due_date"] = NSNull()
        _ = try await phone.applyRemote(entity: "personalDebt", row: JSONSerialization.data(withJSONObject: cleared))
        #expect(try await phone.fetchPersonalDebts().first?.dueDate == nil)
    }

    @Test
    func aColumnThisAppDoesntKnowYetIsIgnored() async throws {
        let phone = try store()
        var pulled = oldRow(updatedAt: "2030-01-01T00:00:00.000Z")
        pulled["due_date"] = "2026-11-15T06:00:00.000Z"
        pulled["a_later_column"] = "x"
        #expect(try await phone.applyRemote(entity: "personalDebt", row: JSONSerialization.data(withJSONObject: pulled)))
        #expect(try await phone.fetchPersonalDebts().first?.dueDate == due)
        #expect(BackupColumns.problem(entity: "personalDebt", row: pulled) == nil)
        pulled.removeValue(forKey: "due_date")
        #expect(BackupColumns.problem(entity: "personalDebt", row: pulled) == nil)
    }

    /// A store written by V12 opens with V13: its debts keep everything and start without a due date.
    @Test
    func versionTwelveStoreMigratesToVersionThirteen() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV12.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            let record = KeepwellSchemaV12.PersonalDebtRecord()
            record.id = id
            record.person = "Ana"
            record.amount = "12"
            record.currency = "USD"
            record.date = due
            context.insert(record)
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let debt = try #require(try await SwiftDataStore(modelContainer: container).fetchPersonalDebts().first)
        #expect(debt.id == id)
        #expect(debt.amount == Money(12, "USD"))
        #expect(debt.dueDate == nil)
    }
}
