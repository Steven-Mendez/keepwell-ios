import Domain
import Foundation
import SwiftData

// The two ways out of a first sync where this device and the account both hold data (keepwell-web
// has the same pair). Either side is kept whole: mixing them would duplicate accounts and movements
// that were entered twice.

extension SwiftDataStore: SyncConflictStore {
    public func localRowCounts() throws(DomainError) -> [String: Int] {
        try perform { context in
            try [
                "account": context.fetchCount(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "card": context.fetchCount(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "transaction": context.fetchCount(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "recurringRule": context.fetchCount(FetchDescriptor<RecurringRuleRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "savingsGoal": context.fetchCount(FetchDescriptor<SavingsGoalRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "loan": context.fetchCount(FetchDescriptor<LoanRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "personalDebt": context.fetchCount(FetchDescriptor<PersonalDebtRecord>(predicate: #Predicate { $0.deletedAt == nil })),
                "categorizationRule": context.fetchCount(
                    FetchDescriptor<CategorizationRuleRecord>(predicate: #Predicate { $0.deletedAt == nil }),
                ),
            ]
        }
    }

    /// All or nothing: the clearing and every row of the account are one save. A row that can't be
    /// read fails the whole replace with this device's data as it was, because the cursor moves
    /// past the snapshot and the row would never come down again.
    public func replaceSyncedData(with rows: [RemoteRow]) throws(DomainError) {
        try perform { context in
            do {
                // Physical deletes: these rows were never the account's, so no tombstone must stay
                // to block the account's copy of a row with the same id (a default category).
                // One by one, not `delete(model:)`: that goes straight to the store and a rollback
                // couldn't bring the rows back.
                try deleteAll(TransactionRecord.self, in: context)
                try deleteAll(RecurringRuleRecord.self, in: context)
                try deleteAll(SavingsGoalRecord.self, in: context)
                try deleteAll(LoanRecord.self, in: context)
                try deleteAll(PersonalDebtRecord.self, in: context)
                try deleteAll(CategorizationRuleRecord.self, in: context)
                try deleteAll(NotificationStateRecord.self, in: context)
                try deleteAll(CardRecord.self, in: context)
                try deleteAll(AccountRecord.self, in: context)
                try deleteAll(CategoryRecord.self, in: context)
                try deleteAll(OutboxRecord.self, in: context)
                // The settings row stays for its device-only columns; the account's row overwrites
                // the synced ones below.
                var unreadable = 0
                for remote in rows where (try? applyRow(remote, in: context)) == nil {
                    unreadable += 1
                }
                guard unreadable == 0 else {
                    throw DomainError.persistence("\(unreadable) rows of the account couldn't be read")
                }
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func deleteAll<Model: PersistentModel>(_: Model.Type, in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(record)
        }
    }

    private func applyRow(_ remote: RemoteRow, in context: ModelContext) throws {
        guard let object = try JSONSerialization.jsonObject(with: remote.row) as? [String: Any] else { throw RowUnreadable() }
        _ = try apply(entity: remote.entity, WireReader(row: object), in: context)
    }

    public func queueFullUpload(replacing rows: [RemoteRow], at now: Date) throws(DomainError) {
        try perform { context in
            var upload = FullUpload(remote: rows, now: now)
            try context.delete(model: OutboxRecord.self)
            try queueLedger(into: &upload, from: context)
            try queueLoansAndDebts(into: &upload, from: context)
            for record in try context.fetch(FetchDescriptor<CategorizationRuleRecord>()) {
                try upload.queue("categorizationRule", record.wireRow())
            }
            for record in try context.fetch(FetchDescriptor<NotificationStateRecord>()) {
                try upload.queue("notificationState", record.wireRow())
            }
            let settings = try context.fetch(FetchDescriptor<SettingsRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            if let record = settings.first {
                upload.queue("settings", record.wireRow())
            }
            upload.queueTombstones()
            for event in upload.events {
                context.enqueue(entity: event.entity, id: event.id, operation: event.operation, row: event.row, at: event.at)
            }
            try context.save()
        }
    }

    private func queueLedger(into upload: inout FullUpload, from context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<AccountRecord>()) {
            try upload.queue("account", record.wireRow())
        }
        for record in try context.fetch(FetchDescriptor<CardRecord>()) {
            try upload.queue("card", record.wireRow())
        }
        for (record, isRemoved) in try uniqueCategoryRows(in: context) {
            var row = try record.wireRow()
            if isRemoved, row["deleted_at"] is NSNull {
                row["deleted_at"] = Wire.date(record.updatedAt)
            }
            upload.queue("category", row)
        }
        for record in try context.fetch(FetchDescriptor<TransactionRecord>()) {
            try upload.queue("transaction", record.wireRow())
        }
        for record in try context.fetch(FetchDescriptor<RecurringRuleRecord>()) {
            try upload.queue("recurringRule", record.wireRow())
        }
        for record in try context.fetch(FetchDescriptor<SavingsGoalRecord>()) {
            try upload.queue("savingsGoal", record.wireRow())
        }
    }

    /// Payments and repayments follow every loan and debt, as `enqueueChild` does: a device can
    /// only attach a payment to a loan it already has.
    private func queueLoansAndDebts(into upload: inout FullUpload, from context: ModelContext) throws {
        let loans = try context.fetch(FetchDescriptor<LoanRecord>())
        for record in loans {
            try upload.queue("loan", record.wireRow())
        }
        for record in loans where record.deletedAt == nil {
            for payment in try record.toDomain().payments {
                upload.queue("loanPayment", record.paymentRow(payment))
            }
        }
        let debts = try context.fetch(FetchDescriptor<PersonalDebtRecord>())
        for record in debts {
            try upload.queue("personalDebt", record.wireRow())
        }
        for record in debts where record.deletedAt == nil {
            for repayment in try record.toDomain().repayments {
                upload.queue("personalDebtRepayment", record.repaymentRow(repayment))
            }
        }
    }
}

private struct RowUnreadable: Error {}

/// The outbox that makes the account match this device, built before anything is written.
private struct FullUpload {
    struct Event {
        let entity: String
        let id: String
        let operation: String
        let row: WireRow
        let at: Date
    }

    private(set) var events: [Event] = []
    /// When the account's copy was last changed, by "entity id".
    private var remoteUpdatedAt: [String: Date] = [:]
    /// The account's live rows, in the order the snapshot listed them.
    private var remoteLive: [(entity: String, id: String, row: WireRow)] = []
    private var queued = Set<String>()
    private let now: Date
    private var clock: Date

    init(remote rows: [RemoteRow], now: Date) {
        self.now = now
        clock = now
        for remote in rows {
            guard let row = try? JSONSerialization.jsonObject(with: remote.row) as? WireRow, let id = row["id"] as? String else { continue }
            let key = Self.key(remote.entity, id)
            if let updated = (row["updated_at"] as? String).flatMap(WireReader.parse) {
                remoteUpdatedAt[key] = updated
            }
            if row["deleted_at"] == nil || row["deleted_at"] is NSNull {
                remoteLive.append((remote.entity, id, row))
            }
        }
    }

    private static func key(_ entity: String, _ id: String) -> String {
        "\(entity) \(id)"
    }

    /// A local row, stamped a millisecond after the account's copy when that copy is as new or
    /// newer: the server keeps the later `updated_at`, so this one wins on every device.
    mutating func queue(_ entity: String, _ row: WireRow) {
        guard let id = row["id"] as? String else { return }
        let key = Self.key(entity, id)
        guard queued.insert(key).inserted else { return }
        var row = row
        let remote = remoteUpdatedAt[key]
        if let remote, let local = (row["updated_at"] as? String).flatMap(WireReader.parse), remote >= local {
            row["updated_at"] = Wire.date(remote.addingTimeInterval(0.001))
        }
        let operation = row["deleted_at"] is NSNull ? (remote == nil ? "create" : "update") : "delete"
        append(entity, id, operation, row)
    }

    /// Every live row of the account that this device doesn't have, deleted. The settings row has
    /// no tombstone: this device's own one has replaced it.
    mutating func queueTombstones() {
        for (entity, id, row) in remoteLive where entity != "settings" && !queued.contains(Self.key(entity, id)) {
            var tombstone = row
            let remote = remoteUpdatedAt[Self.key(entity, id)] ?? now
            tombstone["deleted_at"] = Wire.date(now)
            tombstone["updated_at"] = Wire.date(max(now, remote.addingTimeInterval(0.001)))
            queued.insert(Self.key(entity, id))
            append(entity, id, "delete", tombstone)
        }
    }

    private mutating func append(_ entity: String, _ id: String, _ operation: String, _ row: WireRow) {
        events.append(Event(entity: entity, id: id, operation: operation, row: row, at: clock))
        // Outbox order is send order; a millisecond apart keeps it stable.
        clock = clock.addingTimeInterval(0.001)
    }
}
