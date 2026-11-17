import Domain
import Foundation
import SwiftData

// The one-time download of merchant links after upgrading from a build older than merchants (see
// `SyncEngine+MerchantResync`). A row with a pending local change keeps that change, as ever; only
// the links this device never stored are taken from the account, and its pending events carry them
// too, so pushing the change doesn't clear them on the account.

extension SwiftDataStore {
    @discardableResult
    public func fillMissingMerchantLinks(entity: String, row data: Data) throws(DomainError) -> Bool {
        try perform { context in
            guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            let wire = WireReader(row: row)
            try wire.checkLinks()
            let id = try wire.uuid("id")
            let filled: [String: UUID]
            switch entity {
            case "transaction":
                guard let record = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first,
                      record.deletedAt == nil else { return false }
                filled = try Self.fill(&record.merchantID, &record.viaMerchantID, from: wire)
            case "recurringRule":
                guard let record = try context.fetch(FetchDescriptor<RecurringRuleRecord>(predicate: #Predicate { $0.id == id })).first,
                      record.deletedAt == nil else { return false }
                filled = try Self.fill(&record.merchantID, &record.viaMerchantID, from: wire)
            case "categorizationRule":
                guard let record = try context.fetch(FetchDescriptor<CategorizationRuleRecord>(predicate: #Predicate { $0.id == id }))
                    .first, record.deletedAt == nil else { return false }
                var none: UUID?
                filled = try Self.fill(&record.merchantID, &none, from: wire)
            default:
                return false
            }
            guard !filled.isEmpty else { return false }
            let entityID = Wire.id(id)
            let pending = #Predicate<OutboxRecord> { $0.entityName == entity && $0.entityID == entityID }
            for event in try context.fetch(FetchDescriptor(predicate: pending)) {
                guard var payload = try JSONSerialization.jsonObject(with: Data(event.payload.utf8)) as? [String: Any] else { continue }
                for (key, value) in filled where payload[key] == nil || payload[key] is NSNull {
                    payload[key] = Wire.id(value)
                }
                event.payload = Wire.json(payload)
            }
            // Plain `save()`: the account already has these links, so nothing new is queued.
            try context.save()
            return true
        }
    }

    /// Fills only empty links, never making the platform the business itself. Returns the filled
    /// columns.
    private static func fill(_ merchantID: inout UUID?, _ viaMerchantID: inout UUID?, from wire: WireReader) throws -> [String: UUID] {
        var filled: [String: UUID] = [:]
        if merchantID == nil, let remote = try wire.link("merchant_id"), remote != viaMerchantID {
            merchantID = remote
            filled["merchant_id"] = remote
        }
        if viaMerchantID == nil, let remote = try wire.link("via_merchant_id"), remote != merchantID {
            viaMerchantID = remote
            filled["via_merchant_id"] = remote
        }
        return filled
    }
}
