import Foundation
import SwiftData

// Versions from V12 on live in their own files, so `KeepwellSchema.swift` stays within the lint's
// length; the migration plan and `KeepwellCurrentSchema` stay there.

/// Personal debts carry an optional due date (`dueDate`), synced as `due_date`.
public enum KeepwellSchemaV13: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            // V13's own frozen record (`KeepwellSchemaV13+Records.swift`), not today's.
            AccountRecord.self,
            Persistence.CardRecord.self,
            KeepwellSchemaV14.TransactionRecord.self,
            Persistence.CategoryRecord.self,
            Persistence.SettingsRecord.self,
            KeepwellSchemaV14.RecurringRuleRecord.self,
            SavingsGoalRecord.self,
            LoanRecord.self,
            Persistence.PersonalDebtRecord.self,
            KeepwellSchemaV14.CategorizationRuleRecord.self,
            OutboxRecord.self,
            NotificationStateRecord.self,
        ]
    }
}
