import Domain
import Foundation
import SwiftData
@testable import Persistence

/// A domain value with the audit times of the record that stores it.
struct Stamped<Value: Hashable & Sendable>: Hashable, Sendable {
    let value: Value
    let metadata: RecordMetadata

    init(_ value: Value, _ metadata: RecordMetadata) {
        self.value = value
        self.metadata = metadata
    }
}

/// Everything the store holds, deleted records included, so tests can check tombstones and audit
/// times that the repositories never return.
struct AuditedContents {
    var settings: Stamped<Settings>?
    var accounts: [Stamped<Account>]
    var cards: [Stamped<Card>]
    var categories: [Stamped<TransactionCategory>]
    var transactions: [Stamped<Transaction>]
    var recurringRules: [Stamped<RecurringRule>]
    var savingsGoals: [Stamped<SavingsGoal>]
    var loans: [Stamped<Loan>]
    var personalDebts: [Stamped<PersonalDebt>]
    var categorizationRules: [Stamped<CategorizationRule>]
}

extension SwiftDataStore {
    /// Every record, deleted ones included, with the times it was created, changed and deleted.
    func auditedContents() throws(DomainError) -> AuditedContents {
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
            let goals = try context.fetch(FetchDescriptor<SavingsGoalRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            let loans = try context.fetch(FetchDescriptor<LoanRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            let debts = try context.fetch(FetchDescriptor<PersonalDebtRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            let categorizationRules = try context.fetch(FetchDescriptor<CategorizationRuleRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
                .map { try Stamped($0.toDomain(), $0.metadata) }
            return try AuditedContents(
                settings: settings,
                accounts: accounts,
                cards: cards,
                categories: exportedCategories(in: context),
                transactions: transactions,
                recurringRules: rules,
                savingsGoals: goals,
                loans: loans,
                personalDebts: debts,
                categorizationRules: categorizationRules,
            )
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
}
