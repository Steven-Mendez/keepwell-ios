import Domain
import Foundation
import SwiftData

extension SwiftDataStore: BackupStore {
    /// Every record, deleted ones included, with the times it was created, changed and deleted.
    public func exportContents() throws(DomainError) -> BackupContents {
        try perform { context in
            let settings = try context.fetch(FetchDescriptor<SettingsRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
                .first
                .map { record in try Stamped(record.toDomain(), RecordMetadata(createdAt: record.updatedAt, updatedAt: record.updatedAt)) }
            let accounts = try context.fetch(FetchDescriptor<AccountRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            let cards = try context.fetch(FetchDescriptor<CardRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .filter { !CardRecord.retiredKinds.contains($0.kindRaw) }
                .map { try Stamped($0.toDomain(), $0.metadata) }
            let transactions = try context.fetch(FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            let rules = try context.fetch(FetchDescriptor<RecurringRuleRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            return try BackupContents(
                settings: settings,
                accounts: accounts,
                cards: cards,
                categories: exportedCategories(in: context),
                transactions: transactions,
                recurringRules: rules,
            )
        }
    }

    /// Deletes every record and writes `contents` in one save, keeping ids and audit times, so a
    /// restored record looks to a sync engine like the one that was backed up. On failure the
    /// context is rolled back and nothing changes.
    public func replaceAll(with contents: BackupContents) throws(DomainError) {
        try perform { context in
            do {
                try deleteEveryRecord(in: context)
                if let settings = contents.settings {
                    let record = SettingsRecord().inserted(into: context)
                    record.update(from: settings.value)
                    record.updatedAt = settings.metadata.updatedAt
                }
                for account in contents.accounts {
                    let record = AccountRecord(id: account.value.id).inserted(into: context)
                    record.update(from: account.value)
                    record.apply(account.metadata)
                }
                for card in contents.cards {
                    let record = CardRecord(id: card.value.id).inserted(into: context)
                    record.update(from: card.value)
                    record.apply(card.metadata)
                }
                for (index, category) in contents.categories.enumerated() {
                    let record = CategoryRecord(id: category.value.id).inserted(into: context)
                    record.update(from: category.value, sortIndex: index)
                    record.isRemoved = category.metadata.isDeleted
                    record.apply(category.metadata)
                }
                for transaction in contents.transactions {
                    let record = TransactionRecord(id: transaction.value.id).inserted(into: context)
                    record.update(from: transaction.value)
                    record.apply(transaction.metadata)
                }
                for rule in contents.recurringRules {
                    let record = RecurringRuleRecord(id: rule.value.id).inserted(into: context)
                    record.update(from: rule.value)
                    record.apply(rule.metadata)
                }
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// One row per id, in order. A tombstone written before V5 has no `deletedAt`; its last change
    /// is the best record of when it was deleted.
    private func exportedCategories(in context: ModelContext) throws -> [Stamped<TransactionCategory>] {
        let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
        let removedIDs = Set(records.filter(\.isTombstone).map(\.id))
        var seen = Set<String>()
        return try records.compactMap { record in
            guard seen.insert(record.id).inserted else { return nil }
            let metadata = record.metadata
            let deletedAt = removedIDs.contains(record.id) ? metadata.deletedAt ?? metadata.updatedAt : nil
            return try Stamped(
                record.toDomain(),
                RecordMetadata(createdAt: metadata.createdAt, updatedAt: metadata.updatedAt, deletedAt: deletedAt),
            )
        }
    }

    /// Row by row rather than a batch delete, so the deletions and the inserts that follow land in
    /// the same save and roll back together.
    private func deleteEveryRecord(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<TransactionRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<RecurringRuleRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CardRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<AccountRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CategoryRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SettingsRecord>()).forEach(context.delete)
    }
}
