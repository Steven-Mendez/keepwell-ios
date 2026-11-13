import Foundation
import SwiftData

/// Merchants (`MerchantRecord`), synced as `merchant`, and the links to them: `merchantID` and
/// `viaMerchantID` on movements and recurring rules, `merchantID` on categorization rules.
public enum KeepwellSchemaV15: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(15, 0, 0) }
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
