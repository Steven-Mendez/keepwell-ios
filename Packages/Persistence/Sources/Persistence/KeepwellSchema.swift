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
            AccountRecord.self,
            KeepwellSchemaV3.CardRecord.self,
            TransactionRecord.self,
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
            AccountRecord.self,
            KeepwellSchemaV3.CardRecord.self,
            TransactionRecord.self,
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
            AccountRecord.self,
            CardRecord.self,
            TransactionRecord.self,
            Persistence.CategoryRecord.self,
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
            Persistence.CardRecord.self,
            TransactionRecord.self,
            Persistence.CategoryRecord.self,
            SettingsRecord.self,
        ]
    }
}

/// The schema the app opens today.
public typealias KeepwellCurrentSchema = KeepwellSchemaV4

public enum KeepwellMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [KeepwellSchemaV1.self, KeepwellSchemaV2.self, KeepwellSchemaV3.self, KeepwellSchemaV4.self]
    }

    /// Each step adds optional or defaulted attributes: SwiftData infers the mapping, and CloudKit
    /// accepts additive changes. Rows from V2 start not renamed and not removed, which is true:
    /// V2 couldn't do either to a default. Cards from V3 start with no product name or expiry.
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: KeepwellSchemaV1.self, toVersion: KeepwellSchemaV2.self),
            .lightweight(fromVersion: KeepwellSchemaV2.self, toVersion: KeepwellSchemaV3.self),
            .lightweight(fromVersion: KeepwellSchemaV3.self, toVersion: KeepwellSchemaV4.self),
        ]
    }
}
