import Foundation
import OSLog
import SwiftData

/// Where data is stored.
public enum PersistenceStore: Sendable, Equatable {
    /// Memory only (tests, previews, UI tests).
    case inMemory
    /// On the device. Keepwell's own sync (the account) keeps other devices up to date.
    case local
}

public enum ModelContainerFactory {
    private static let logger = Logger(subsystem: "Persistence", category: "ModelContainer")

    /// Creates the `ModelContainer` for the current schema.
    public static func make(store: PersistenceStore) throws -> ModelContainer {
        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let configuration = switch store {
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .local:
            ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        logger.info("Creating ModelContainer: \(String(describing: store), privacy: .public)")
        return try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: configuration,
        )
    }
}
