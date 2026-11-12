import Foundation
import SwiftData

// Versioned schema. Register `@Model` types in the latest version; when the model changes, freeze
// the previous shape of the changed records inside its version and add a stage to
// `KeepwellMigrationPlan`.
//
// CloudKit requirements for every `@Model`: all properties optional or defaulted,
// no `@Attribute(.unique)`, and optional relationships.

public enum KeepwellSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            KeepwellSchemaV4.AccountRecord.self,
            KeepwellSchemaV3.CardRecord.self,
            KeepwellSchemaV4.TransactionRecord.self,
            CategoryRecord.self,
            SettingsRecord.self,
        ]
    }

    /// The category row before people could pick an icon and a color.
    @Model
    public final class CategoryRecord {
        public var id = ""
        var name = ""
        var kindRaw = "expense"
        var sortIndex = 0

        init(id: String, name: String, kindRaw: String, sortIndex: Int) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.sortIndex = sortIndex
        }
    }
}

/// Categories gain `icon` and `color`, for the ones people create.
public enum KeepwellSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            KeepwellSchemaV4.AccountRecord.self,
            KeepwellSchemaV3.CardRecord.self,
            KeepwellSchemaV4.TransactionRecord.self,
            CategoryRecord.self,
            SettingsRecord.self,
        ]
    }

    /// The category row before defaults could be renamed or deleted.
    @Model
    public final class CategoryRecord {
        public var id = ""
        var name = ""
        var kindRaw = "expense"
        var sortIndex = 0
        var icon: String?
        var color: String?

        init(id: String, name: String, kindRaw: String, sortIndex: Int, icon: String? = nil, color: String? = nil) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.sortIndex = sortIndex
            self.icon = icon
            self.color = color
        }
    }
}

/// Managed default categories: a default can be renamed (`isRenamed`) and deleted, leaving a
/// tombstone (`isRemoved`) so it isn't seeded again. Self-contained on purpose: if another branch
/// also adds a version, renumber this one and its stage when merging.
public enum KeepwellSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            KeepwellSchemaV4.AccountRecord.self,
            CardRecord.self,
            KeepwellSchemaV4.TransactionRecord.self,
            KeepwellSchemaV4.CategoryRecord.self,
            SettingsRecord.self,
        ]
    }

    /// The card row before plastics kept their product name and expiry. V1 and V2 share it: cards
    /// didn't change until V4.
    @Model
    public final class CardRecord {
        public var id = UUID()
        var accountID = UUID()
        var kindRaw = "debit"
        var networkRaw: String?
        var lastFour: String?
        var colorRaw: String?
        var holderName: String?
        var capAmount: String?
        var capCurrency: String?
        var allowedCategoryIDs = ""
        var defaultCategoryID: String?
        var alertEachPurchase = true
        var alertNearCap = true
        var isFrozen = false
        var createdAt = Date.now

        init(id: UUID, accountID: UUID, kindRaw: String, lastFour: String? = nil) {
            self.id = id
            self.accountID = accountID
            self.kindRaw = kindRaw
            self.lastFour = lastFour
        }
    }
}

/// Cards gain a product name and an expiry month and year.
public enum KeepwellSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            AccountRecord.self,
            CardRecord.self,
            TransactionRecord.self,
            CategoryRecord.self,
            SettingsRecord.self,
        ]
    }

    /// The account row before records kept `updatedAt` and `deletedAt`. V1 to V3 share it.
    @Model
    public final class AccountRecord {
        public var id = UUID()
        var name = ""
        var bank: String?
        var kindRaw = "deposit"
        var openingBalances = ""
        var openingDate = Date.distantPast
        var debtModeRaw: String?
        var limitAmount: String?
        var limitCurrency: String?
        var cutoffDay: Int?
        var dueDay: Int?
        var createdAt = Date.now

        init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// The card row with product name and expiry, before audit dates.
    @Model
    public final class CardRecord {
        public var id = UUID()
        var accountID = UUID()
        var kindRaw = "debit"
        var networkRaw: String?
        var lastFour: String?
        var colorRaw: String?
        var holderName: String?
        var capAmount: String?
        var capCurrency: String?
        var allowedCategoryIDs = ""
        var defaultCategoryID: String?
        var alertEachPurchase = true
        var alertNearCap = true
        var isFrozen = false
        var createdAt = Date.now
        var productName: String?
        var expiryMonth: Int?
        var expiryYear: Int?

        init(id: UUID, accountID: UUID, kindRaw: String) {
            self.id = id
            self.accountID = accountID
            self.kindRaw = kindRaw
        }
    }

    /// The movement row before audit dates. V1 to V3 share it.
    @Model
    public final class TransactionRecord {
        public var id = UUID()
        var date = Date.distantPast
        var statusRaw = "confirmed"
        var descriptionText = ""
        var kindRaw = "expense"
        var categoryID: String?
        var amount = "0"
        var currency = ""
        var accountID = UUID()
        var cardID: UUID?
        var destinationAccountID: UUID?
        var actualDebitedPrincipal: String?
        var ratePrincipal = ""
        var rateSecond = ""
        var rate = "1"
        var isShared = false
        var note: String?

        #Index<TransactionRecord>([\.date])

        init(id: UUID, date: Date, amount: String, currency: String, accountID: UUID) {
            self.id = id
            self.date = date
            self.amount = amount
            self.currency = currency
            self.accountID = accountID
            ratePrincipal = currency
            rateSecond = currency
        }
    }

    /// The category row with rename and tombstone flags, before audit dates. V3 shares it.
    @Model
    public final class CategoryRecord {
        public var id = ""
        var name = ""
        var kindRaw = "expense"
        var sortIndex = 0
        var icon: String?
        var color: String?
        var isRenamed = false
        var isRemoved = false

        init(id: String, name: String, kindRaw: String, sortIndex: Int) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.sortIndex = sortIndex
        }
    }
}

/// Records keep `createdAt`, `updatedAt` and `deletedAt`: deletes become tombstones, ready for a
/// sync engine (CloudKit or Keepwell's own) to merge copies by their last change.
public enum KeepwellSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            TransactionRecord.self,
            KeepwellSchemaV6.CategoryRecord.self,
            SettingsRecord.self,
        ]
    }

    /// The movement row with audit dates, before it named the recurring rule that recorded it.
    @Model
    public final class TransactionRecord {
        public var id = UUID()
        var date = Date.distantPast
        var statusRaw = "confirmed"
        var descriptionText = ""
        var kindRaw = "expense"
        var categoryID: String?
        var amount = "0"
        var currency = ""
        var accountID = UUID()
        var cardID: UUID?
        var destinationAccountID: UUID?
        var actualDebitedPrincipal: String?
        var ratePrincipal = ""
        var rateSecond = ""
        var rate = "1"
        var isShared = false
        var note: String?
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        #Index<TransactionRecord>([\.date])

        init(id: UUID, date: Date, amount: String, currency: String, accountID: UUID) {
            self.id = id
            self.date = date
            self.amount = amount
            self.currency = currency
            self.accountID = accountID
            ratePrincipal = currency
            rateSecond = currency
        }
    }
}

/// Recurring rules (`RecurringRuleRecord`), and movements remember the rule that recorded them.
public enum KeepwellSchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            KeepwellSchemaV8.TransactionRecord.self,
            CategoryRecord.self,
            SettingsRecord.self,
            KeepwellSchemaV8.RecurringRuleRecord.self,
        ]
    }

    /// The category row with audit dates, before it carried a monthly budget. V5 shares it.
    @Model
    public final class CategoryRecord {
        public var id = ""
        var name = ""
        var kindRaw = "expense"
        var sortIndex = 0
        var icon: String?
        var color: String?
        var isRenamed = false
        var isRemoved = false
        var createdAt = Date.now
        var updatedAt = Date.now
        var deletedAt: Date?

        init(id: String, name: String, kindRaw: String, sortIndex: Int) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.sortIndex = sortIndex
        }
    }
}

/// Expense categories carry an optional monthly budget (`budgetAmount`, `budgetCurrency`).
public enum KeepwellSchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            KeepwellSchemaV8.TransactionRecord.self,
            Persistence.CategoryRecord.self,
            SettingsRecord.self,
            KeepwellSchemaV8.RecurringRuleRecord.self,
        ]
    }
}

/// Savings goals (`SavingsGoalRecord`).
public enum KeepwellSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            TransactionRecord.self,
            Persistence.CategoryRecord.self,
            SettingsRecord.self,
            RecurringRuleRecord.self,
            SavingsGoalRecord.self,
        ]
    }
}

/// Loans (`LoanRecord`), personal debts (`PersonalDebtRecord`), categorization rules
/// (`CategorizationRuleRecord`), and tags on movements and recurring rules (`tagsText`).
public enum KeepwellSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            Persistence.TransactionRecord.self,
            Persistence.CategoryRecord.self,
            SettingsRecord.self,
            Persistence.RecurringRuleRecord.self,
            SavingsGoalRecord.self,
            LoanRecord.self,
            PersonalDebtRecord.self,
            CategorizationRuleRecord.self,
        ]
    }
}

/// The sync outbox (`OutboxRecord`), and who created each movement and recurring rule (`sourceRaw`).
public enum KeepwellSchemaV10: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [
            Persistence.AccountRecord.self,
            Persistence.CardRecord.self,
            Persistence.TransactionRecord.self,
            Persistence.CategoryRecord.self,
            SettingsRecord.self,
            Persistence.RecurringRuleRecord.self,
            SavingsGoalRecord.self,
            LoanRecord.self,
            PersonalDebtRecord.self,
            CategorizationRuleRecord.self,
            OutboxRecord.self,
        ]
    }
}

/// What the person did with each notification (`NotificationStateRecord`).
public enum KeepwellSchemaV11: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        KeepwellSchemaV10.models + [NotificationStateRecord.self]
    }
}

/// The schema the app opens today.
public typealias KeepwellCurrentSchema = KeepwellSchemaV11

public enum KeepwellMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            KeepwellSchemaV1.self,
            KeepwellSchemaV2.self,
            KeepwellSchemaV3.self,
            KeepwellSchemaV4.self,
            KeepwellSchemaV5.self,
            KeepwellSchemaV6.self,
            KeepwellSchemaV7.self,
            KeepwellSchemaV8.self,
            KeepwellSchemaV9.self,
            KeepwellSchemaV10.self,
            KeepwellSchemaV11.self,
        ]
    }

    /// Each step adds optional or defaulted attributes: SwiftData infers the mapping, and CloudKit
    /// accepts additive changes. Rows from V2 start not renamed and not removed, which is true:
    /// V2 couldn't do either to a default. Cards from V3 start with no product name or expiry.
    /// Rows from V4 start alive (`deletedAt` nil), changed at the time of the migration. Movements
    /// from V5 start without a recurring rule, and there are no rules yet. Categories from V6 start
    /// without a budget. V7 had no savings goals, so V8 starts with none,
    /// and V8 had no loans, personal debts or categorization rules, so V9 starts with none; its
    /// movements and recurring rules start without tags. V10 starts with an empty outbox and every
    /// movement and rule made in the app (`sourceRaw` nil reads as `app`). V11 adds notification
    /// states, none yet.
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: KeepwellSchemaV1.self, toVersion: KeepwellSchemaV2.self),
            .lightweight(fromVersion: KeepwellSchemaV2.self, toVersion: KeepwellSchemaV3.self),
            .lightweight(fromVersion: KeepwellSchemaV3.self, toVersion: KeepwellSchemaV4.self),
            .lightweight(fromVersion: KeepwellSchemaV4.self, toVersion: KeepwellSchemaV5.self),
            .lightweight(fromVersion: KeepwellSchemaV5.self, toVersion: KeepwellSchemaV6.self),
            .lightweight(fromVersion: KeepwellSchemaV6.self, toVersion: KeepwellSchemaV7.self),
            .lightweight(fromVersion: KeepwellSchemaV7.self, toVersion: KeepwellSchemaV8.self),
            .lightweight(fromVersion: KeepwellSchemaV8.self, toVersion: KeepwellSchemaV9.self),
            .lightweight(fromVersion: KeepwellSchemaV9.self, toVersion: KeepwellSchemaV10.self),
            .lightweight(fromVersion: KeepwellSchemaV10.self, toVersion: KeepwellSchemaV11.self),
        ]
    }
}
