import Domain
import Foundation
import SwiftData

extension SwiftDataStore: MerchantRepository {
    public func fetchMerchants() throws(DomainError) -> [Merchant] {
        try perform { context in
            try context.fetch(FetchDescriptor<MerchantRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .map { $0.toDomain() }
        }
    }

    /// Throws `.notFound` for a merchant deleted meanwhile (a pull can bring its tombstone while
    /// the editor is open): saving it must not bring it back.
    public func save(_ merchant: Merchant) throws(DomainError) {
        try perform { context in
            guard try upsert(merchant, in: context) else { throw DomainError.notFound(merchant.id) }
            try context.saveWithOutbox()
        }
    }

    public func deleteMerchant(id: UUID) throws(DomainError) {
        try perform { context in
            try tombstone(merchant: id, in: context)
            try context.saveWithOutbox()
        }
    }

    public func commit(_ changes: MerchantChanges) throws(DomainError) {
        try perform { context in
            do {
                for transaction in changes.transactions {
                    let id = transaction.id
                    let record = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first
                        ?? TransactionRecord(id: id).inserted(into: context)
                    record.update(from: transaction)
                    record.stampSaved()
                }
                for rule in changes.recurringRules {
                    let id = rule.id
                    let record = try context.fetch(FetchDescriptor<RecurringRuleRecord>(predicate: #Predicate { $0.id == id })).first
                        ?? RecurringRuleRecord(id: id).inserted(into: context)
                    record.update(from: rule)
                    record.stampSaved()
                }
                for rule in changes.categorizationRules {
                    let id = rule.id
                    // Only a rule that is here: a repair never brings back one deleted meanwhile.
                    guard let record = try context.fetch(FetchDescriptor<CategorizationRuleRecord>(predicate: #Predicate { $0.id == id }))
                        .first
                    else { continue }
                    record.update(from: rule, sortIndex: record.sortIndex)
                    record.stampSaved()
                }
                // A merchant deleted meanwhile stays deleted; the repair after the next pull
                // unlinks whatever this commit still points at it.
                for merchant in changes.savedMerchants {
                    try upsert(merchant, in: context)
                }
                for id in changes.deletedMerchantIDs {
                    try tombstone(merchant: id, in: context)
                }
                for id in changes.deletedCategoryIDs {
                    try tombstoneCategory(id: id, in: context)
                }
                try context.saveWithOutbox()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// Ids of the merchants that are tombstones here, for the repair after a pull.
    public func deletedMerchantIDs() throws(DomainError) -> Set<UUID> {
        try perform { context in
            try Set(context.fetch(FetchDescriptor<MerchantRecord>()).filter { $0.deletedAt != nil }.map(\.id))
        }
    }

    /// `false`, writing nothing, when the stored merchant is a tombstone: `stampSaved()` would
    /// clear its `deletedAt` and revive a merchant another device deleted.
    @discardableResult
    private func upsert(_ merchant: Merchant, in context: ModelContext) throws -> Bool {
        let id = merchant.id
        let stored = try context.fetch(FetchDescriptor<MerchantRecord>(predicate: #Predicate { $0.id == id })).first
        if stored?.deletedAt != nil {
            return false
        }
        let record = stored ?? MerchantRecord(id: id).inserted(into: context)
        record.update(from: merchant)
        record.stampSaved()
        return true
    }

    private func tombstone(merchant id: UUID, in context: ModelContext) throws {
        let alive = #Predicate<MerchantRecord> { $0.id == id && $0.deletedAt == nil }
        guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
            throw DomainError.notFound(id)
        }
        record.stampDeleted()
    }
}
