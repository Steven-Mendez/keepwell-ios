import Domain
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
    func migrationPlanGoesThroughEveryVersion() {
        #expect(KeepwellSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(KeepwellSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(KeepwellSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(KeepwellMigrationPlan.schemas.count == 3)
        #expect(KeepwellMigrationPlan.stages.count == 2)
        #expect(KeepwellSchemaV1.models.count == 5)
        #expect(KeepwellSchemaV2.models.count == 5)
        #expect(KeepwellSchemaV3.models.count == 5)
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
        let records = try ModelContext(container).fetch(FetchDescriptor<KeepwellSchemaV2.CategoryRecord>())
        let migrated = try #require(records.first)
        #expect(records.count == 1)
        #expect(migrated.name == "Market")
        #expect(migrated.icon == nil)
        #expect(migrated.color == nil)
    }

    /// A store written by V2 opens with V3: its categories keep icon and color, and start neither
    /// renamed nor removed, so every default still translates and shows.
    @Test
    func versionTwoStoreMigratesToVersionThree() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            context.insert(KeepwellSchemaV2.CategoryRecord(id: "groceries", name: "Groceries", kindRaw: "expense", sortIndex: 0))
            context.insert(KeepwellSchemaV2.CategoryRecord(
                id: "custom-boat", name: "Boat", kindRaw: "expense", sortIndex: 1, icon: "sailboat", color: "blue",
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellSchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let records = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(records.map(\.id) == ["groceries", "custom-boat"])
        #expect(records.allSatisfy { !$0.isRenamed && !$0.isRemoved })
        #expect(records.last?.icon == "sailboat")
        #expect(records.last?.color == "blue")

        let categories = try await SwiftDataStore(modelContainer: container).fetchCategories()
        #expect(categories.first { $0.id == "groceries" }?.translatesByID == true)
        #expect(categories.count == TransactionCategory.defaults.count + 1)
    }
}
