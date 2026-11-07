import Domain
import DomainSamples
import Foundation
import Testing
@testable import Persistence

/// Every local change leaves an event in the outbox, in the same save, as a row the API accepts.
@Suite("Sync outbox")
struct OutboxTests {
    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private struct Column: Decodable {
        let type: String
        let nullable: Bool
        let optional: Bool
    }

    private func columns() throws -> [String: [String: Column]] {
        struct File: Decodable {
            let entities: [String: [String: Column]]
        }
        let url = try #require(Bundle.module.url(forResource: "wire-columns", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).entities
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    /// The row has exactly the wire columns, required ones present (nullable as null), types right.
    private func expectWireShape(_ event: OutboxEvent, _ columns: [String: [String: Column]]) throws {
        let expected = try #require(columns[event.entity], "unknown entity \(event.entity)")
        let row = try row(event)
        #expect(
            Set(row.keys).isSubset(of: Set(expected.keys)),
            "\(event.entity) has extra keys \(Set(row.keys).subtracting(expected.keys))",
        )
        for (name, column) in expected where !column.optional {
            let value = try #require(row[name], "\(event.entity).\(name) missing")
            if value is NSNull {
                #expect(column.nullable, "\(event.entity).\(name) is null")
                continue
            }
            switch column.type {
            case "string": #expect(value is String, "\(event.entity).\(name)")
            case "number": #expect(!isBoolean(value) && value is NSNumber, "\(event.entity).\(name)")
            case "boolean": #expect(
                    isBoolean(value),
                    "\(event.entity).\(name)",
                )
            case "array": #expect(value is [Any], "\(event.entity).\(name)")
            default: break
            }
        }
        #expect(row["id"] as? String == event.entityID)
    }

    @Test
    func everySampleChangeIsQueuedAsAWireRow() async throws {
        let store = try store()
        let sample = SampleData.standard
        try await store.save(sample.settings)
        for account in sample.accounts {
            try await store.save(account)
        }
        for card in sample.cards {
            try await store.save(card)
        }
        for transaction in sample.transactions.prefix(5) {
            try await store.save(transaction)
        }
        for loan in sample.loans {
            try await store.save(loan)
        }
        for debt in sample.personalDebts {
            try await store.save(debt)
        }
        let events = try await store.pendingEvents(limit: 500)
        let columns = try columns()
        #expect(Set(events.map(\.entity)).isSuperset(of: [
            "settings",
            "account",
            "card",
            "transaction",
            "loan",
            "loanPayment",
            "personalDebt",
        ]))
        for event in events {
            try expectWireShape(event, columns)
        }
        let settings = try row(#require(events.first { $0.entity == "settings" }))
        #expect(settings["unlock_method"] == nil)
    }

    @Test
    func payingAnInstallmentQueuesThatPaymentOnlyAndUndoingItQueuesItsDeletion() async throws {
        let store = try store()
        let loan = try #require(SampleData.standard.loans.first)
        try await store.save(loan.with(payments: []))
        try await store.removeEvents(ids: store.pendingEvents().map(\.id))

        let paid = loan.with(payments: [LoanPayment(number: 1, paidAt: .now)])
        try await store.save(paid)
        let payments = try await store.pendingEvents().filter { $0.entity == "loanPayment" }
        #expect(payments.map(\.operation) == ["create"])
        #expect(payments.first?.entityID == NameBasedID.loanPayment(loanID: loan.id, number: 1).uuidString.lowercased())

        try await store.removeEvents(ids: store.pendingEvents().map(\.id))
        try await store.save(paid.with(payments: []))
        #expect(try await store.pendingEvents().filter { $0.entity == "loanPayment" }.map(\.operation) == ["delete"])
    }

    @Test
    func aDeletionIsQueuedAsATombstone() async throws {
        let store = try store()
        let account = try #require(SampleData.standard.accounts.first)
        try await store.save(account)
        try await store.deleteAccount(id: account.id)
        let last = try #require(try await store.pendingEvents().last)
        #expect(last.operation == "delete")
        #expect(try row(last)["deleted_at"] is String)
    }

    @Test
    func erasingThisIPhoneLeavesNothingToSend() async throws {
        let store = try store()
        try await store.save(SampleData.standard.settings)
        try await store.eraseAll()
        #expect(await store.pendingCount() == 0)
    }

    /// Foundation bridges every NSNumber to Bool, so only the CF type tells a JSON boolean apart.
    private func isBoolean(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }
}
