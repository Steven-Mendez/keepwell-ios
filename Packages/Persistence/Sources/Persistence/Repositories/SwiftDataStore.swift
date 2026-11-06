import Domain
import Foundation
import SwiftData

/// Serializes all SwiftData access on one background actor and implements every shared
/// repository protocol, so features get protocols and never a `ModelContext`.
@ModelActor
public actor SwiftDataStore {
    func perform<T>(_ work: (ModelContext) throws -> T) throws(DomainError) -> T {
        do {
            return try work(modelContext)
        } catch let corruption as DomainCorruption {
            throw .corruptedData(corruption.message)
        } catch let error as DomainError {
            throw error
        } catch {
            throw .persistence(String(describing: error))
        }
    }

    func saveChanges() throws(DomainError) {
        try perform { context in try context.save() }
    }
}

extension SwiftDataStore: AccountRepository {
    public func fetchAccounts() throws(DomainError) -> [Account] {
        try perform { context in
            try context.fetch(FetchDescriptor<AccountRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .map { try $0.toDomain() }
        }
    }

    public func save(_ account: Account) throws(DomainError) {
        try perform { context in
            let id = account.id
            let record = try context.fetch(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })).first
                ?? AccountRecord(id: id).inserted(into: context)
            record.update(from: account)
            record.stampSaved()
            try context.save()
        }
    }

    public func deleteAccount(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<AccountRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }
}

extension SwiftDataStore: CardRepository {
    public func fetchCards() throws(DomainError) -> [Card] {
        try perform { context in
            try context.fetch(FetchDescriptor<CardRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .filter { !CardRecord.retiredKinds.contains($0.kindRaw) }
            .map { try $0.toDomain() }
        }
    }

    public func save(_ card: Card) throws(DomainError) {
        try perform { context in
            let id = card.id
            let record = try context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.id == id })).first
                ?? CardRecord(id: id).inserted(into: context)
            record.update(from: card)
            record.stampSaved()
            try context.save()
        }
    }

    public func deleteCard(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<CardRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }
}

extension SwiftDataStore: TransactionRepository {
    public func fetchTransactions(in period: DateInterval?) throws(DomainError) -> [Transaction] {
        try perform { context in
            var descriptor = FetchDescriptor<TransactionRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.date, order: .reverse)],
            )
            if let period {
                let start = period.start
                let end = period.end
                descriptor.predicate = #Predicate { $0.deletedAt == nil && $0.date >= start && $0.date < end }
            }
            return try context.fetch(descriptor).map { try $0.toDomain() }
        }
    }

    public func save(_ transaction: Transaction) throws(DomainError) {
        try perform { context in
            let id = transaction.id
            let record = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first
                ?? TransactionRecord(id: id).inserted(into: context)
            record.update(from: transaction)
            record.stampSaved()
            try context.save()
        }
    }

    public func deleteTransaction(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<TransactionRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }
}

extension SwiftDataStore: RecurringRuleRepository {
    public func fetchRecurringRules() throws(DomainError) -> [RecurringRule] {
        try perform { context in
            try context.fetch(FetchDescriptor<RecurringRuleRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .map { try $0.toDomain() }
        }
    }

    public func save(_ rule: RecurringRule) throws(DomainError) {
        try perform { context in
            try upsert(rule, in: context)
            try context.save()
        }
    }

    public func deleteRecurringRule(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<RecurringRuleRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }

    public func saveMaterialized(transactions: [Transaction], rules: [RecurringRule]) throws(DomainError) {
        try perform { context in
            do {
                for transaction in transactions {
                    let id = transaction.id
                    let record = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first
                        ?? TransactionRecord(id: id).inserted(into: context)
                    record.update(from: transaction)
                    record.stampSaved()
                }
                for rule in rules {
                    try upsert(rule, in: context)
                }
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func upsert(_ rule: RecurringRule, in context: ModelContext) throws {
        let id = rule.id
        let record = try context.fetch(FetchDescriptor<RecurringRuleRecord>(predicate: #Predicate { $0.id == id })).first
            ?? RecurringRuleRecord(id: id).inserted(into: context)
        record.update(from: rule)
        record.stampSaved()
    }
}

extension SwiftDataStore: SavingsGoalRepository {
    public func fetchSavingsGoals() throws(DomainError) -> [SavingsGoal] {
        try perform { context in
            try context.fetch(FetchDescriptor<SavingsGoalRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .map { try $0.toDomain() }
        }
    }

    public func save(_ goal: SavingsGoal) throws(DomainError) {
        try perform { context in
            let id = goal.id
            let record = try context.fetch(FetchDescriptor<SavingsGoalRecord>(predicate: #Predicate { $0.id == id })).first
                ?? SavingsGoalRecord(id: id).inserted(into: context)
            record.update(from: goal)
            record.stampSaved()
            try context.save()
        }
    }

    public func deleteSavingsGoal(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<SavingsGoalRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }
}

extension SwiftDataStore: CategoryRepository {
    public func fetchCategories() throws(DomainError) -> [TransactionCategory] {
        try perform { context in
            var rows = try uniqueCategoryRows(in: context)
            // A first launch, and an update that ships new defaults, both get the missing ones;
            // a tombstone counts as present, so a deleted default stays deleted.
            let present = Set(rows.map(\.record.id))
            let missing = TransactionCategory.defaults.filter { !present.contains($0.id) }
            var next = (rows.map(\.record.sortIndex).max() ?? -1) + 1
            for category in missing {
                let record = CategoryRecord(id: category.id).inserted(into: context)
                record.update(from: category, sortIndex: next)
                record.stampSaved()
                next += 1
                rows.append((record, false))
            }
            if !missing.isEmpty {
                try context.save()
            }
            return try TransactionCategory.ordered(rows.filter { !$0.isRemoved }.map { try $0.record.toDomain() })
        }
    }

    public func save(_ category: TransactionCategory) throws(DomainError) {
        try perform { context in
            let id = category.id
            let existing = try context.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id }))
            let last = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])).first
            let record = existing.first ?? CategoryRecord(id: id).inserted(into: context)
            record.update(from: category, sortIndex: existing.first?.sortIndex ?? (last.map { $0.sortIndex + 1 } ?? 0))
            record.stampSaved()
            // Saving a default that another device deleted brings it back on every row.
            for duplicate in existing.dropFirst() {
                duplicate.isRemoved = false
                duplicate.stampSaved()
            }
            try context.save()
        }
    }

    public func deleteCategory(id: String) throws(DomainError) {
        try perform { context in
            let records = try context.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id }))
            var tombstones = records
            // A default deleted before it was ever seeded still needs its tombstone, or the next
            // fetch would seed it back. A created category that isn't stored has nothing to delete.
            if records.isEmpty, let shipped = TransactionCategory.shipped(id: id) {
                let last = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])).first
                let record = CategoryRecord(id: id).inserted(into: context)
                record.update(from: shipped, sortIndex: last.map { $0.sortIndex + 1 } ?? 0)
                record.createdAt = .now
                tombstones = [record]
            }
            for record in tombstones where !record.isTombstone {
                record.isRemoved = true
                record.stampDeleted()
            }
            try context.save()
        }
    }

    public func reorderCategories(ids: [String]) throws(DomainError) {
        try perform { context in
            let rank = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
            let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
            let listed = records.filter { rank[$0.id] != nil }.sorted { rank[$0.id] ?? 0 < rank[$1.id] ?? 0 }
            for (index, record) in (listed + records.filter { rank[$0.id] == nil }).enumerated() where record.sortIndex != index {
                record.sortIndex = index
                record.updatedAt = .now
            }
            try context.save()
        }
    }

    public func restoreDefaultCategories() throws(DomainError) {
        try perform { context in
            let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
            var byID: [String: [CategoryRecord]] = [:]
            for record in records {
                byID[record.id, default: []].append(record)
            }
            for (index, category) in TransactionCategory.defaults.enumerated() {
                let rows = byID[category.id] ?? [CategoryRecord(id: category.id).inserted(into: context)]
                for record in rows {
                    record.update(from: category, sortIndex: index)
                    record.stampSaved()
                }
            }
            let created = records.filter { TransactionCategory.shipped(id: $0.id) == nil }
            for (offset, record) in created.enumerated() where record.sortIndex != TransactionCategory.defaults.count + offset {
                record.sortIndex = TransactionCategory.defaults.count + offset
                record.updatedAt = .now
            }
            try context.save()
        }
    }

    /// One row per id. Two devices can each write the same default before syncing: the first
    /// row wins, and a delete on either device removes it.
    private func uniqueCategoryRows(in context: ModelContext) throws -> [(record: CategoryRecord, isRemoved: Bool)] {
        let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
        var removedIDs = Set<String>()
        for record in records where record.isTombstone {
            removedIDs.insert(record.id)
        }
        var seen = Set<String>()
        return records.compactMap { record in
            guard seen.insert(record.id).inserted else { return nil }
            return (record, removedIDs.contains(record.id))
        }
    }
}

extension SwiftDataStore: SettingsRepository {
    public func load() throws(DomainError) -> Settings? {
        try perform { context in
            // Two devices may each create a row before syncing; the latest edit wins.
            try context.fetch(FetchDescriptor<SettingsRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
                .first?
                .toDomain()
        }
    }

    public func save(_ settings: Settings) throws(DomainError) {
        try perform { context in
            let records = try context.fetch(FetchDescriptor<SettingsRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            let record = records.first ?? SettingsRecord().inserted(into: context)
            for duplicate in records.dropFirst() {
                context.delete(duplicate)
            }
            record.update(from: settings)
            try context.save()
        }
    }
}

extension SwiftDataStore: DataEraser {
    /// The one physical delete: the person asked for their data to be gone, so no tombstones stay.
    /// Deleting the records locally also deletes them from the CloudKit private database when
    /// mirroring is on, which erases the iCloud copy.
    public func eraseAll() throws(DomainError) {
        try perform { context in
            try context.delete(model: TransactionRecord.self)
            try context.delete(model: RecurringRuleRecord.self)
            try context.delete(model: SavingsGoalRecord.self)
            try context.delete(model: LoanRecord.self)
            try context.delete(model: PersonalDebtRecord.self)
            try context.delete(model: CategorizationRuleRecord.self)
            try context.delete(model: CardRecord.self)
            try context.delete(model: AccountRecord.self)
            try context.delete(model: CategoryRecord.self)
            try context.delete(model: SettingsRecord.self)
            try context.save()
        }
    }
}

extension PersistentModel {
    @discardableResult
    func inserted(into context: ModelContext) -> Self {
        context.insert(self)
        return self
    }
}
