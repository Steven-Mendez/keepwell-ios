import Foundation
import OSLog
import SwiftData

/// Where data is stored.
public enum PersistenceStore: Sendable, Equatable {
    /// Memory only (tests, previews, UI tests).
    case inMemory
    /// On device only, without iCloud (the user turned backup off).
    case local
    /// On device + CloudKit private database.
    case cloudKit(containerIdentifier: String)
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
        case let .cloudKit(identifier):
            ModelConfiguration(schema: schema, cloudKitDatabase: .private(identifier))
        }
        logger.info("Creating ModelContainer: \(String(describing: store), privacy: .public)")
        return try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: configuration,
        )
    }
}
