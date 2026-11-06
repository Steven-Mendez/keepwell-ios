import Domain
import Foundation
import SwiftData

extension SwiftDataStore: LoanRepository {
    public func fetchLoans() throws(DomainError) -> [Loan] {
        try perform { context in
            try context.fetch(FetchDescriptor<LoanRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .map { try $0.toDomain() }
        }
    }

    public func save(_ loan: Loan) throws(DomainError) {
        try perform { context in
            try upsert(loan, in: context)
            try context.save()
        }
    }

    public func deleteLoan(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<LoanRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }

    public func save(_ loan: Loan, recording transaction: Transaction) throws(DomainError) {
        try perform { context in
            do {
                let transactionID = transaction.id
                let movement = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == transactionID })).first
                    ?? TransactionRecord(id: transactionID).inserted(into: context)
                movement.update(from: transaction)
                movement.stampSaved()
                try upsert(loan, in: context)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func save(_ loan: Loan, deletingTransaction transactionID: UUID?) throws(DomainError) {
        try perform { context in
            do {
                if let transactionID {
                    let alive = #Predicate<TransactionRecord> { $0.id == transactionID && $0.deletedAt == nil }
                    try context.fetch(FetchDescriptor(predicate: alive)).first?.stampDeleted()
                }
                try upsert(loan, in: context)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func upsert(_ loan: Loan, in context: ModelContext) throws {
        let id = loan.id
        let record = try context.fetch(FetchDescriptor<LoanRecord>(predicate: #Predicate { $0.id == id })).first
            ?? LoanRecord(id: id).inserted(into: context)
        record.update(from: loan)
        record.stampSaved()
    }
}

extension SwiftDataStore: PersonalDebtRepository {
    public func fetchPersonalDebts() throws(DomainError) -> [PersonalDebt] {
        try perform { context in
            try context.fetch(FetchDescriptor<PersonalDebtRecord>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.createdAt)],
            ))
            .map { try $0.toDomain() }
        }
    }

    public func save(_ debt: PersonalDebt) throws(DomainError) {
        try perform { context in
            let id = debt.id
            let record = try context.fetch(FetchDescriptor<PersonalDebtRecord>(predicate: #Predicate { $0.id == id })).first
                ?? PersonalDebtRecord(id: id).inserted(into: context)
            record.update(from: debt)
            record.stampSaved()
            try context.save()
        }
    }

    public func deletePersonalDebt(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<PersonalDebtRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            try context.save()
        }
    }
}
