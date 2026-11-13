import Domain
import Foundation
import Testing
@testable import Persistence

/// `sync-v1.json` is keepwell-web's `sync.json` as it was when the format shipped, frozen, and
/// keepwell-web and keepwell-api run it too. Phones and the server already hold rows like these, so
/// this iPhone must still read each one and write it back with every column it came with: a column
/// renamed or dropped on either side (`ApplyRemote` or `WireRows`) fails here.
@Suite("Sync format v1")
struct SyncFormatV1Tests {
    private struct Case {
        let name: String
        let entity: String
        let entityID: String
        let payload: [String: Any]
    }

    /// Only the server writes these, and no client stores them.
    private static let serverColumns: Set = ["user_id", "server_seq", "applied_at"]
    /// The time the v1 rows were written, given to the loan a payment row needs to land in.
    private static let rowTime = "2026-11-01T18:00:00.000Z"

    private func file() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "sync-v1", withExtension: "json", subdirectory: "Fixtures"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func cases() throws -> [Case] {
        let valid = try #require(file()["valid"] as? [[String: Any]])
        return try valid.map { item in
            let event = try #require(item["event"] as? [String: Any])
            return try Case(
                name: #require(item["name"] as? String),
                entity: #require(event["entity"] as? String),
                entityID: #require(event["entity_id"] as? String),
                payload: #require(event["payload"] as? [String: Any]),
            )
        }
    }

    /// One JSON value as canonical text, so `false`, `0`, `null` and `[]` compare as JSON does.
    private func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test
    func isVersionOne() throws {
        #expect(try file()["version"] as? Int == 1)
    }

    @Test
    func everyRowIsReadAndWrittenBackWithAllItsColumns() async throws {
        for item in try cases() {
            let payload = item.payload
            let store = try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
            if item.entity == "loanPayment" {
                // A payment only lands in a loan this iPhone has; its audit columns are the loan's.
                let loanID = try #require(payload["loan_id"] as? String)
                try await store.applyRemote(entity: "loan", row: JSONSerialization.data(withJSONObject: [
                    "id": loanID, "name": "Préstamo", "lender": NSNull(), "borrowed_amount": "1000", "borrowed_currency": "USD",
                    "installment_amount": "100", "installment_count": 12, "frequency": "monthly", "first_due_date": Self.rowTime,
                    "created_at": Self.rowTime, "updated_at": Self.rowTime, "deleted_at": NSNull(),
                ]))
            }
            let applied = try await store.applyRemote(
                entity: item.entity,
                row: JSONSerialization.data(withJSONObject: payload),
            )
            #expect(applied, "\(item.name) wasn't applied")

            try await store.queueFullUpload(replacing: [], at: .now)
            let event = try await store.pendingEvents(limit: 1000)
                .first { $0.entity == item.entity && $0.entityID == item.entityID }
            let written = try #require(event, "\(item.name) isn't written back")
            let row = try #require(JSONSerialization.jsonObject(with: written.payload) as? [String: Any])
            for (column, value) in payload where !Self.serverColumns.contains(column) {
                let back = try #require(row[column], "\(item.name): \(item.entity).\(column) is lost")
                #expect(try json(back) == json(value), "\(item.name): \(item.entity).\(column)")
            }
        }
    }
}
