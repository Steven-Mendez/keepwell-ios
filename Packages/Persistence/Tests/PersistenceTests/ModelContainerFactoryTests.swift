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
    func schemaStartsAtVersionOne() {
        #expect(KeepwellSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(KeepwellMigrationPlan.schemas.count == 1)
        #expect(KeepwellSchemaV1.models.count == 1)
    }
}
