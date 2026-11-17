import Foundation
import SwiftData

/// The settings row carries the person's home time zone (`timeZone`), synced as `time_zone`.
public enum KeepwellSchemaV12: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(12, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            KeepwellSchemaV13.AccountRecord.self,
            Persistence.CardRecord.self,
            KeepwellSchemaV14.TransactionRecord.self,
            Persistence.CategoryRecord.self,
            Persistence.SettingsRecord.self,
            KeepwellSchemaV14.RecurringRuleRecord.self,
            SavingsGoalRecord.self,
            LoanRecord.self,
            // V12's own frozen record (`KeepwellSchemaV12+Records.swift`), not today's.
            PersonalDebtRecord.self,
            KeepwellSchemaV14.CategorizationRuleRecord.self,
            OutboxRecord.self,
            NotificationStateRecord.self,
        ]
    }
}
