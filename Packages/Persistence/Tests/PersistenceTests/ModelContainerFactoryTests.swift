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
        #expect(KeepwellSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(KeepwellSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
        #expect(KeepwellSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(KeepwellSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(KeepwellSchemaV8.versionIdentifier == Schema.Version(8, 0, 0))
        #expect(KeepwellMigrationPlan.schemas.count == 8)
        #expect(KeepwellMigrationPlan.stages.count == 7)
        #expect(KeepwellSchemaV1.models.count == 5)
        #expect(KeepwellSchemaV2.models.count == 5)
        #expect(KeepwellSchemaV3.models.count == 5)
        #expect(KeepwellSchemaV4.models.count == 5)
        #expect(KeepwellSchemaV5.models.count == 5)
        #expect(KeepwellSchemaV6.models.count == 6)
        #expect(KeepwellSchemaV7.models.count == 6)
        #expect(KeepwellSchemaV8.models.count == 7)
    }

    /// A store written by V3 opens with today's schema: cards keep their digits and start with no
    /// product name or expiry, which the person adds later.
    @Test
    func versionThreeStoreMigratesToVersionFour() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")
        let cardID = UUID()

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV3.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            context.insert(KeepwellSchemaV3.CardRecord(id: cardID, accountID: UUID(), kindRaw: "creditHolder", lastFour: "0633"))
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let cards = try await SwiftDataStore(modelContainer: container).fetchCards()
        let card = try #require(cards.first { $0.id == cardID })
        #expect(card.lastFour == "0633")
        #expect(card.productName == nil)
        #expect(card.expiry == nil)
    }

    /// Product name and expiry survive a save and a read.
    @Test
    func cardDetailsRoundTrip() async throws {
        let store = try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
        let card = try Card(
            accountID: UUID(), kind: .creditHolder, network: .visa, lastFour: "0842",
            productName: "Platinum Walmart", expiry: CardExpiry(month: 2, year: 2028),
        )
        try await store.save(card)
        let saved = try #require(await store.fetchCards().first { $0.id == card.id })
        #expect(saved.productName == "Platinum Walmart")
        #expect(try saved.expiry == CardExpiry(month: 2, year: 2028))
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

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
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

    /// A store written by V4 opens with today's schema: every record is alive, keeps its data and
    /// gets audit dates, so nothing disappears behind the `deletedAt` filter. It opens the current
    /// schema, not V5, because the store reads categories with today's record.
    @Test
    func versionFourStoreMigratesToVersionFive() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")
        let accountID = UUID()
        let transactionID = UUID()
        let cardID = UUID()

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV4.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            let account = KeepwellSchemaV4.AccountRecord(id: accountID, name: "BAC")
            account.openingBalances = "USD:10.5"
            context.insert(account)
            context.insert(KeepwellSchemaV4.CardRecord(id: cardID, accountID: accountID, kindRaw: "debit"))
            context.insert(KeepwellSchemaV4.TransactionRecord(
                id: transactionID, date: .now, amount: "12.34", currency: "USD", accountID: accountID,
            ))
            context.insert(KeepwellSchemaV4.CategoryRecord(id: "custom-boat", name: "Boat", kindRaw: "expense", sortIndex: 0))
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellCurrentSchema.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let store = SwiftDataStore(modelContainer: container)
        #expect(try await store.fetchAccounts().map(\.id) == [accountID])
        #expect(try await store.fetchCards().map(\.id) == [cardID])
        let transaction = try #require(await store.fetchTransactions(in: nil).first)
        #expect(transaction.id == transactionID)
        #expect(transaction.amount == Decimal(string: "12.34"))
        #expect(try await store.fetchCategories().contains { $0.id == "custom-boat" })
        let contents = try await store.exportContents()
        #expect(contents.accounts.allSatisfy { !$0.metadata.isDeleted })
        #expect(contents.transactions.allSatisfy { !$0.metadata.isDeleted })
    }

    /// A store written by V5 opens with V6: movements keep everything and name no rule, and there
    /// are no rules until the person creates one.
    @Test
    func versionFiveStoreMigratesToVersionSix() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")
        let transactionID = UUID()

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV5.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            context.insert(KeepwellSchemaV5.TransactionRecord(
                id: transactionID, date: .now, amount: "12.34", currency: "USD", accountID: UUID(),
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellSchemaV6.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let store = SwiftDataStore(modelContainer: container)
        let transaction = try #require(await store.fetchTransactions(in: nil).first)
        #expect(transaction.id == transactionID)
        #expect(transaction.amount == Decimal(string: "12.34"))
        #expect(transaction.recurringID == nil)
        #expect(try await store.fetchRecurringRules().isEmpty)
    }

    /// A store written by V6 opens with V7: categories keep everything and start without a budget.
    @Test
    func versionSixStoreMigratesToVersionSeven() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV6.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let context = ModelContext(container)
            let boat = KeepwellSchemaV6.CategoryRecord(id: "custom-boat", name: "Boat", kindRaw: "expense", sortIndex: 0)
            boat.icon = "sailboat"
            context.insert(boat)
            try context.save()
        }

        let schema = Schema(versionedSchema: KeepwellSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let store = SwiftDataStore(modelContainer: container)
        let boat = try #require(await store.fetchCategories().first { $0.id == "custom-boat" })
        #expect(boat.name == "Boat")
        #expect(boat.icon == "sailboat")
        #expect(boat.monthlyBudget == nil)
    }
}

extension ModelContainerFactoryTests {
    /// A store written by V7 opens with V8: everything stays, and there are no goals until the
    /// person creates one.
    @Test
    func versionSevenStoreMigratesToVersionEight() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Keepwell.store")

        do {
            let schema = Schema(versionedSchema: KeepwellSchemaV7.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let store = SwiftDataStore(modelContainer: container)
            try await store.save(TransactionCategory(
                id: "custom-boat", name: "Boat", kind: .expense, monthlyBudget: Money(250, "USD"),
            ))
        }

        let schema = Schema(versionedSchema: KeepwellSchemaV8.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: KeepwellMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let store = SwiftDataStore(modelContainer: container)
        let boat = try #require(await store.fetchCategories().first { $0.id == "custom-boat" })
        #expect(boat.monthlyBudget == Money(250, "USD"))
        #expect(try await store.fetchSavingsGoals().isEmpty)
        let goal = SavingsGoal(name: "Trip", target: Money(15000, "NIO"))
        try await store.save(goal)
        #expect(try await store.fetchSavingsGoals() == [goal])
    }
}
