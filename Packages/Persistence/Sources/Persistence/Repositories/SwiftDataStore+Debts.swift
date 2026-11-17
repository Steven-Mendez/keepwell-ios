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
            try context.saveWithOutbox()
        }
    }

    public func deleteLoan(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<LoanRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            for payment in try record.toDomain().payments {
                let row = record.paymentRow(payment, deletedAt: record.updatedAt)
                context.enqueueChild(entity: "loanPayment", id: row["id"] as? String ?? "", operation: "delete", row: row)
            }
            try context.saveWithOutbox()
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
                try context.saveWithOutbox()
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
                try context.saveWithOutbox()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// Each payment syncs as its own row (ADR 0005 in keepwell-api), so the ones added or undone
    /// here are queued one by one, next to the loan's own event.
    private func upsert(_ loan: Loan, in context: ModelContext) throws {
        let id = loan.id
        let existing = try context.fetch(FetchDescriptor<LoanRecord>(predicate: #Predicate { $0.id == id })).first
        let before = try existing?.toDomain().payments ?? []
        let record = existing ?? LoanRecord(id: id).inserted(into: context)
        record.update(from: loan)
        record.stampSaved()
        enqueuePaymentChanges(of: record, before: before, after: loan.payments, in: context)
    }

    private func enqueuePaymentChanges(of record: LoanRecord, before: [LoanPayment], after: [LoanPayment], in context: ModelContext) {
        let previous = Dictionary(uniqueKeysWithValues: before.map { ($0.number, $0) })
        let current = Dictionary(uniqueKeysWithValues: after.map { ($0.number, $0) })
        for payment in after where previous[payment.number] != payment {
            let row = record.paymentRow(payment)
            context.enqueueChild(
                entity: "loanPayment",
                id: row["id"] as? String ?? "",
                operation: previous[payment.number] == nil ? "create" : "update",
                row: row,
            )
        }
        for payment in before where current[payment.number] == nil {
            let row = record.paymentRow(payment, deletedAt: record.updatedAt)
            context.enqueueChild(entity: "loanPayment", id: row["id"] as? String ?? "", operation: "delete", row: row)
        }
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
            try upsert(debt, in: context)
            try context.saveWithOutbox()
        }
    }

    public func fetchRepaymentDepositIDs() throws(DomainError) -> [UUID] {
        try perform { context in
            // Tombstoned debts too: their repayments stay in the record.
            var seen = Set<UUID>()
            return try context.fetch(FetchDescriptor<PersonalDebtRecord>(sortBy: [SortDescriptor(\.createdAt)]))
                .flatMap(\.depositIDs)
                .filter { seen.insert($0).inserted }
        }
    }

    public func save(_ debt: PersonalDebt, recording transaction: Transaction) throws(DomainError) {
        try perform { context in
            do {
                let transactionID = transaction.id
                let movement = try context.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == transactionID })).first
                    ?? TransactionRecord(id: transactionID).inserted(into: context)
                movement.update(from: transaction)
                movement.stampSaved()
                try upsert(debt, in: context)
                try context.saveWithOutbox()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func save(_ debt: PersonalDebt, deletingTransaction transactionID: UUID?) throws(DomainError) {
        try perform { context in
            do {
                if let transactionID {
                    let alive = #Predicate<TransactionRecord> { $0.id == transactionID && $0.deletedAt == nil }
                    try context.fetch(FetchDescriptor(predicate: alive)).first?.stampDeleted()
                }
                try upsert(debt, in: context)
                try context.saveWithOutbox()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// Each repayment syncs as its own row (ADR 0005 in keepwell-api). Only repayments added or
    /// removed here are queued: a repayment never changes once recorded, so the ones already stored
    /// (also those written before `transaction_id` existed) aren't sent again with every save.
    private func upsert(_ debt: PersonalDebt, in context: ModelContext) throws {
        let id = debt.id
        let existing = try context.fetch(FetchDescriptor<PersonalDebtRecord>(predicate: #Predicate { $0.id == id })).first
        let before = try existing?.toDomain().repayments ?? []
        let record = existing ?? PersonalDebtRecord(id: id).inserted(into: context)
        record.update(from: debt)
        record.stampSaved()
        let previous = Set(before.map(\.id))
        let current = Set(debt.repayments.map(\.id))
        for repayment in debt.repayments where !previous.contains(repayment.id) {
            context.enqueueChild(
                entity: "personalDebtRepayment",
                id: repayment.id.uuidString.lowercased(),
                operation: "create",
                row: record.repaymentRow(repayment),
            )
        }
        for repayment in before where !current.contains(repayment.id) {
            context.enqueueChild(
                entity: "personalDebtRepayment",
                id: repayment.id.uuidString.lowercased(),
                operation: "delete",
                row: record.repaymentRow(repayment, deletedAt: record.updatedAt),
            )
        }
    }

    public func deletePersonalDebt(id: UUID) throws(DomainError) {
        try perform { context in
            let alive = #Predicate<PersonalDebtRecord> { $0.id == id && $0.deletedAt == nil }
            guard let record = try context.fetch(FetchDescriptor(predicate: alive)).first else {
                throw DomainError.notFound(id)
            }
            record.stampDeleted()
            for repayment in try record.toDomain().repayments {
                context.enqueueChild(
                    entity: "personalDebtRepayment",
                    id: repayment.id.uuidString.lowercased(),
                    operation: "delete",
                    row: record.repaymentRow(repayment, deletedAt: record.updatedAt),
                )
            }
            try context.saveWithOutbox()
        }
    }
}
