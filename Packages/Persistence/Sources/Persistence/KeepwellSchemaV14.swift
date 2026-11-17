import Foundation
import SwiftData

/// Accounts can be closed (`closedAt`), synced as `closed_at`: a closed account keeps its history.
public enum KeepwellSchemaV14: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            // V14's own frozen records (`KeepwellSchemaV14+Records.swift`), not today's.
            TransactionRecord.self,
            Persistence.CategoryRecord.self,
            Persistence.SettingsRecord.self,
            RecurringRuleRecord.self,
            SavingsGoalRecord.self,
            LoanRecord.self,
            Persistence.PersonalDebtRecord.self,
            CategorizationRuleRecord.self,
            OutboxRecord.self,
            NotificationStateRecord.self,
        ]
    }
}
