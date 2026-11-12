import Domain
import Foundation
import SwiftData

extension SwiftDataStore: CategorizationRuleRepository {
    public func fetchCategorizationRules() throws(DomainError) -> [CategorizationRule] {
        try perform { context in
            try context.fetch(FetchDescriptor<CategorizationRuleRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)],
            ))
            .map { try $0.toDomain() }
        }
    }

    public func save(_ rule: CategorizationRule) throws(DomainError) {
        try perform { context in
            let id = rule.id
            let existing = try context.fetch(FetchDescriptor<CategorizationRuleRecord>(predicate: #Predicate { $0.id == id })).first
            let last = try context.fetch(FetchDescriptor<CategorizationRuleRecord>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]))
                .first
            let record = existing ?? CategorizationRuleRecord(id: id).inserted(into: context)
            record.update(from: rule, sortIndex: existing?.sortIndex ?? (last.map { $0.sortIndex + 1 } ?? 0))
            record.stampSaved()
            try context.saveWithOutbox()
        }
    }

    public func deleteCategorizationRule(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<CategorizationRuleRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.saveWithOutbox()
        }
    }

    public func reorderCategorizationRules(ids: [UUID]) throws(DomainError) {
        try perform { context in
            let rank = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
            let records = try context.fetch(FetchDescriptor<CategorizationRuleRecord>(
                sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)],
            ))
            let listed = records.filter { rank[$0.id] != nil }.sorted { rank[$0.id] ?? 0 < rank[$1.id] ?? 0 }
            for (index, record) in (listed + records.filter { rank[$0.id] == nil }).enumerated() where record.sortIndex != index {
                record.sortIndex = index
                record.stampChanged()
            }
            try context.saveWithOutbox()
        }
    }
}
