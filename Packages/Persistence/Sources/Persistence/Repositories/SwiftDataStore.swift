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
            try context.fetch(FetchDescriptor<AccountRecord>(sortBy: [SortDescriptor(\.createdAt)])).map { try $0.toDomain() }
        }
    }

    public func save(_ account: Account) throws(DomainError) {
        try perform { context in
            let id = account.id
            let record = try context.fetch(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })).first
                ?? AccountRecord(id: id).inserted(into: context)
            record.update(from: account)
            try context.save()
        }
    }

    public func deleteAccount(id: UUID) throws(DomainError) {
        try perform { context in
            guard let record = try context.fetch(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })).first else {
                throw DomainError.notFound(id)
            }
            context.delete(record)
            try context.save()
        }
    }
}

extension SwiftDataStore: CardRepository {
    public func fetchCards() throws(DomainError) -> [Card] {
        try perform { context in
            try context.fetch(FetchDescriptor<CardRecord>(sortBy: [SortDescriptor(\.createdAt)])).map { try $0.toDomain() }
        }
    }

    public func save(_ card: Card) throws(DomainError) {
        try perform { context in
            let id = card.id
            let record = try context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.id == id })).first
                ?? CardRecord(id: id).inserted(into: context)
            record.update(from: card)
            try context.save()
        }
    }

    public func deleteCard(id: UUID) throws(DomainError) {
        try perform { context in
            guard let record = try context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.id == id })).first else {
                throw DomainError.notFound(id)
            }
            context.delete(record)
            try context.save()
        }
    }
}

extension SwiftDataStore: TransactionRepository {
    public func fetchTransactions(in period: DateInterval?) throws(DomainError) -> [Transaction] {
        try perform { context in
            var descriptor = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            if let period {
                let start = period.start
                let end = period.end
                descriptor.predicate = #Predicate { $0.date >= start && $0.date < end }
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
            try context.save()
        }
    }

    public func deleteTransaction(id: UUID) throws(DomainError) {
        try perform { context in
            guard let record = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first
            else { throw DomainError.notFound(id) }
            context.delete(record)
            try context.save()
        }
    }
}

extension SwiftDataStore: CategoryRepository {
    public func fetchCategories() throws(DomainError) -> [TransactionCategory] {
        try perform { context in
            let records = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
            // Two devices can each write the same default before syncing; the first row wins.
            var byID: [String: CategoryRecord] = [:]
            var unique: [CategoryRecord] = []
            for record in records where byID[record.id] == nil {
                byID[record.id] = record
                unique.append(record)
            }
            // A first launch, and an update that ships new defaults, both get the missing ones.
            let missing = TransactionCategory.defaults.enumerated().filter { byID[$0.element.id] == nil }
            for (index, category) in missing {
                let record = CategoryRecord(id: category.id).inserted(into: context)
                record.update(from: category, sortIndex: index)
                unique.append(record)
            }
            if !missing.isEmpty {
                try context.save()
            }
            return try TransactionCategory.ordered(unique.map { try $0.toDomain() })
        }
    }

    public func save(_ category: TransactionCategory) throws(DomainError) {
        try perform { context in
            let id = category.id
            let existing = try context.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })).first
            let last = try context.fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])).first
            let record = existing ?? CategoryRecord(id: id).inserted(into: context)
            record.update(from: category, sortIndex: existing?.sortIndex ?? (last.map { $0.sortIndex + 1 } ?? 0))
            try context.save()
        }
    }

    public func deleteCategory(id: String) throws(DomainError) {
        try perform { context in
            for record in try context.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })) {
                context.delete(record)
            }
            try context.save()
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
    /// Deleting the records locally also deletes them from the CloudKit private database when
    /// mirroring is on, which erases the iCloud copy.
    public func eraseAll() throws(DomainError) {
        try perform { context in
            try context.delete(model: TransactionRecord.self)
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
