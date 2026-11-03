import SwiftData

/// Versioned schema. Register `@Model` types here; when the model changes, add
/// `KeepwellSchemaV2` plus a stage in `KeepwellMigrationPlan`.
///
/// CloudKit requirements for every `@Model`: all properties optional or defaulted,
/// no `@Attribute(.unique)`, and optional relationships.
public enum KeepwellSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [] }
}

public enum KeepwellMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [KeepwellSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
