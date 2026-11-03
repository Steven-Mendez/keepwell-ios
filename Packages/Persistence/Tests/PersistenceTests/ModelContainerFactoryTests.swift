import Foundation
import SwiftData
import Testing
@testable import Persistence

@Suite("ModelContainerFactory")
struct ModelContainerFactoryTests {
    @Test
    func makesInMemoryContainer() throws {
        let container = try ModelContainerFactory.make(store: .inMemory)
        let configuration = try #require(container.configurations.first)
        #expect(configuration.isStoredInMemoryOnly)
    }

    @Test
    func migrationPlanGoesFromVersionOneToTwo() {
        #expect(KeepwellSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(KeepwellSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(KeepwellMigrationPlan.schemas.count == 2)
        #expect(KeepwellMigrationPlan.stages.count == 1)
        #expect(KeepwellSchemaV1.models.count == 5)
        #expect(KeepwellSchemaV2.models.count == 5)
    }

    /// A store written by V1 opens with V2 and keeps its categories, now without icon or color.
    @Test
    func versionOneStoreMigratesToVersionTwo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            context.insert(KeepwellSchemaV1.CategoryRecord(id: "groceries", name: "Market", kindRaw: "expense", sortIndex: 0))
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let records = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
        let migrated = try #require(records.first)
        #expect(records.count == 1)
        #expect(migrated.name == "Market")
        #expect(migrated.icon == nil)
        #expect(migrated.color == nil)
    }
}
