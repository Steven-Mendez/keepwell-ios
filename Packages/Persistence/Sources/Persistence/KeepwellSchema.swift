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
            CardRecord.self,
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
            CardRecord.self,
            TransactionRecord.self,
            Persistence.CategoryRecord.self,
            SettingsRecord.self,
        ]
    }
}

public enum KeepwellMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [KeepwellSchemaV1.self, KeepwellSchemaV2.self] }
    /// Two optional attributes: SwiftData infers the mapping, and CloudKit accepts additive changes.
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: KeepwellSchemaV1.self, toVersion: KeepwellSchemaV2.self)]
    }
}
