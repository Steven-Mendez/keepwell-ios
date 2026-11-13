import Domain
import Foundation
import SwiftData

// The full backup, the same file keepwell-web writes and reads (`lib/backup/format.ts`):
// `{ "format": "keepwell-backup", "version": 2, "exported_at": …, "entities": { "<entity>": [row…] } }`,
// every row in the sync wire format. A version this app doesn't know is refused, not half read.
// Version 2 adds `account.closed_at`: a column that changes what the person sees raises the version,
// so an app that predates it refuses the file instead of reopening closed accounts without a word.
// Version 1 files still restore (their accounts are open).

enum BackupFile {
    static let format = "keepwell-backup"
    static let version = 2
    static let entities = [
        "account", "card", "category", "transaction", "recurringRule", "savingsGoal", "loan", "loanPayment",
        "personalDebt", "personalDebtRepayment", "categorizationRule", "settings", "notificationState",
    ]
    /// Settings first, so the currencies arrive before any movement in them; then parents before children.
    static let importOrder = ["settings"] + entities.filter { $0 != "settings" }
}

extension SwiftDataStore: LedgerBackupStore {
    public func exportBackup(at now: Date) throws(DomainError) -> Data {
        try perform { context in
            var entities = Dictionary(uniqueKeysWithValues: BackupFile.entities.map { ($0, [WireRow]()) })
            for (entity, row) in try allWireRows(in: context) {
                entities[entity, default: []].append(row)
            }
            let file: [String: Any] = [
                "format": BackupFile.format, "version": BackupFile.version, "exported_at": Wire.date(now), "entities": entities,
            ]
            return try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
        }
    }

    public func isLedgerEmpty() throws(DomainError) -> Bool {
        try perform { context in try ledgerIsEmpty(in: context) }
    }

    /// All or nothing: the whole file is checked first, then every row is stored with its outbox event
    /// in one save, stamped now (after the backup's `updated_at`) so the account takes it over whatever
    /// it holds for the same id. Any row that fails rolls everything back.
    public func importBackup(_ data: Data, at now: Date) throws(BackupRestoreError) {
        let rows = try Self.readBackup(data)
        // One synchronous actor call: nothing else writes between the check and the restore.
        let isEmpty: Bool
        do {
            isEmpty = try isLedgerEmpty()
        } catch {
            throw .failed
        }
        guard isEmpty else { throw .notEmpty }
        do {
            try perform { context in
                do {
                    try restore(rows, at: now, in: context)
                    try context.save()
                } catch {
                    context.rollback()
                    throw error
                }
            }
        } catch {
            if case let .corruptedData(message) = error {
                throw .invalid(message)
            }
            throw .failed
        }
        NotificationCenter.default.post(name: .keepwellOutboxChanged, object: nil)
    }

    private func restore(_ rows: [(entity: String, row: WireRow)], at now: Date, in context: ModelContext) throws {
        // Every category here is a shipped default (the ledger is empty): they go, so the backup's
        // version of each, deleted ones included, is what stays. Defaults it lacks are seeded again.
        for record in try context.fetch(FetchDescriptor<CategoryRecord>()) {
            context.delete(record)
        }
        let wasOnboarded = try context.fetch(FetchDescriptor<SettingsRecord>()).contains(where: \.hasCompletedOnboarding)
        var clock = now
        for (entity, original) in rows {
            var row = original
            let updated = (row["updated_at"] as? String).flatMap(WireReader.parse)
            row["updated_at"] = Wire.date(stampAfter(updated, now: now))
            if entity == "settings", wasOnboarded {
                row["has_completed_onboarding"] = true
            }
            // `false`: a row this app keeps inside another that is gone (a deleted loan's payment).
            guard try apply(entity: entity, WireReader(row: row), in: context) else { continue }
            let operation = row["deleted_at"] is NSNull ? "create" : "delete"
            context.enqueue(entity: entity, id: row["id"] as? String ?? "", operation: operation, row: row, at: clock)
            clock = clock.addingTimeInterval(0.001)
        }
        try checkDomain(in: context)
    }

    /// Every stored row still reads as a domain value (kinds, currencies, decimals).
    private func checkDomain(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<AccountRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<CardRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<CategoryRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<TransactionRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<RecurringRuleRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<SavingsGoalRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<LoanRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<PersonalDebtRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<CategorizationRuleRecord>()) {
            _ = try record.toDomain()
        }
        for record in try context.fetch(FetchDescriptor<SettingsRecord>()) {
            _ = try record.toDomain()
        }
    }

    func ledgerIsEmpty(in context: ModelContext) throws -> Bool {
        let counts = try [
            context.fetchCount(FetchDescriptor<AccountRecord>()),
            context.fetchCount(FetchDescriptor<CardRecord>()),
            context.fetchCount(FetchDescriptor<TransactionRecord>()),
            context.fetchCount(FetchDescriptor<RecurringRuleRecord>()),
            context.fetchCount(FetchDescriptor<SavingsGoalRecord>()),
            // Payments and repayments live inside these two.
            context.fetchCount(FetchDescriptor<LoanRecord>()),
            context.fetchCount(FetchDescriptor<PersonalDebtRecord>()),
            context.fetchCount(FetchDescriptor<CategorizationRuleRecord>()),
        ]
        guard counts.allSatisfy({ $0 == 0 }) else { return false }
        return try context.fetch(FetchDescriptor<CategoryRecord>()).allSatisfy { TransactionCategory.shipped(id: $0.id) != nil }
    }

    /// The file's rows in import order, or why it can't be restored. Checks the envelope and every
    /// row's columns (`BackupColumns`) before anything is written.
    static func readBackup(_ data: Data) throws(BackupRestoreError) -> [(entity: String, row: WireRow)] {
        guard let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              file["format"] as? String == BackupFile.format
        else { throw .notBackup }
        guard let version = file["version"] as? Int, version >= 1 else { throw .invalid("version") }
        guard version <= BackupFile.version else { throw .newerVersion(version) }
        guard file["exported_at"] is String else { throw .invalid("exported_at") }
        guard let entities = file["entities"] as? [String: Any] else { throw .invalid("entities") }
        if let unknown = entities.keys.first(where: { !BackupFile.entities.contains($0) }) {
            throw .invalid("entities: unknown entity \(unknown.prefix(40))")
        }
        var rows: [(entity: String, row: WireRow)] = []
        for entity in BackupFile.importOrder {
            guard let list = (entities[entity] ?? [Any]()) as? [Any] else { throw .invalid("\(entity): not a list") }
            if entity == "settings", list.count > 1 {
                throw .invalid("settings: more than one row")
            }
            try rows += readRows(list, of: entity)
        }
        return rows
    }

    /// One entity's rows, each well formed and with an id of its own.
    private static func readRows(_ list: [Any], of entity: String) throws(BackupRestoreError) -> [(entity: String, row: WireRow)] {
        var seen = Set<String>()
        var rows: [(entity: String, row: WireRow)] = []
        for (index, item) in list.enumerated() {
            guard let row = item as? WireRow else { throw .invalid("\(entity)[\(index)]: row") }
            if let column = BackupColumns.problem(entity: entity, row: row) {
                throw .invalid("\(entity)[\(index)]: \(column)")
            }
            let id = (row["id"] as? String ?? "").lowercased()
            guard seen.insert(id).inserted else { throw .invalid("\(entity)[\(index)]: duplicate id") }
            rows.append((entity, row))
        }
        return rows
    }
}
