import Foundation
import SwiftData

/// Movements can carry a shared split's public link (`shareToken`), synced as `share_token`.
public enum KeepwellSchemaV16: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            Persistence.TransactionRecord.self,
            Persistence.CategoryRecord.self,
            Persistence.SettingsRecord.self,
            Persistence.RecurringRuleRecord.self,
            SavingsGoalRecord.self,
            LoanRecord.self,
            Persistence.PersonalDebtRecord.self,
            Persistence.CategorizationRuleRecord.self,
            OutboxRecord.self,
            NotificationStateRecord.self,
            MerchantRecord.self,
        ]
    }
}
