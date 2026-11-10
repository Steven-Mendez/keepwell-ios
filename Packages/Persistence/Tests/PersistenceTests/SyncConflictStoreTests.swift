import Domain
import DomainSamples
import Foundation
import Testing
@testable import Persistence

/// The two ways out of a first sync where this iPhone and the account both hold data.
@Suite("Sync conflict resolutions")
struct SyncConflictStoreTests {
    private let sample = SampleData.standard

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    /// This iPhone: the sample data, locked with the app passcode only.
    private func device() async throws -> SwiftDataStore {
        let store = try makeStore()
        var settings = sample.settings
        settings.unlockMethod = .passcode
        settings.relockAfter = 900
        try await store.seed(
            settings: settings,
            accounts: sample.accounts,
            cards: sample.cards,
            transactions: sample.transactions,
            categories: sample.categories,
            recurringRules: sample.recurringRules,
            savingsGoals: sample.savingsGoals,
            loans: sample.loans,
            personalDebts: sample.personalDebts,
            categorizationRules: sample.categorizationRules,
        )
        return store
    }

    private let cloudAccount = Account(
        id: UUID(),
        name: "From the web",
        kind: .cash,
        openingBalances: [Money(50, "EUR")],
        openingDate: Date(timeIntervalSince1970: 1_790_000_000),
    )

    /// The account's rows as the snapshot would send them: another store's wire rows.
    private func cloudRows() async throws -> [RemoteRow] {
        let cloud = try makeStore()
        try await cloud.save(Settings(currencies: CurrencySettings(principal: "EUR", second: nil, rate: 1), hasCompletedOnboarding: true))
        try await cloud.save(cloudAccount)
        return try await cloud.pendingEvents(limit: 1000).map { RemoteRow(entity: $0.entity, row: $0.payload) }
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    @Test
    func countsOnlyLiveUserData() async throws {
        let store = try await device()
        let counts = try await store.localRowCounts()
        #expect(counts["account"] == sample.accounts.count)
        #expect(counts["transaction"] == sample.transactions.count)
        #expect(counts["category"] == nil)

        let empty = try makeStore()
        _ = try await empty.fetchCategories()
        #expect(try await empty.localRowCounts().values.allSatisfy { $0 == 0 })
    }

    @Test
    func usingTheAccountsDataReplacesEverythingSyncedButKeepsThisIPhonesOwnSettings() async throws {
        let store = try await device()
        #expect(await store.pendingCount() > 0)

        try await store.replaceSyncedData(with: cloudRows())

        #expect(try await store.fetchAccounts().map(\.name) == ["From the web"])
        #expect(try await store.fetchTransactions(in: nil).isEmpty)
        #expect(try await store.fetchSavingsGoals().isEmpty)
        #expect(await store.pendingCount() == 0)
        let settings = try #require(try await store.load())
        #expect(settings.currencies.principal == "EUR")
        #expect(settings.hasCompletedOnboarding)
        // How this iPhone unlocks never travels, so the account's settings leave it alone.
        #expect(settings.unlockMethod == .passcode)
        #expect(settings.relockAfter == 900)
        // No tombstones of the old data stay behind to block the account's rows.
        let contents = try await store.auditedContents()
        #expect(contents.transactions.isEmpty)
        #expect(contents.accounts.count == 1)
    }

    /// The cursor moves past the snapshot, so a row skipped here would never come down again.
    @Test
    func aRowThatCantBeReadFailsTheReplaceAndLeavesThisIPhoneAsItWas() async throws {
        let store = try await device()
        let pending = await store.pendingCount()
        let broken = RemoteRow(entity: "transaction", row: Data(#"{"id":"\#(UUID().uuidString)","amount":"1"}"#.utf8))
        await #expect(throws: DomainError.self) {
            try await store.replaceSyncedData(with: [broken] + cloudRows())
        }
        #expect(try await store.fetchAccounts().count == sample.accounts.count)
        #expect(try await store.fetchTransactions(in: nil).count == sample.transactions.count)
        #expect(try await store.fetchSavingsGoals().count == sample.savingsGoals.count)
        #expect(await store.pendingCount() == pending)
        let settings = try #require(try await store.load())
        #expect(settings.unlockMethod == .passcode)
    }

    @Test
    func keepingThisIPhonesDataUploadsEveryRowAndDeletesWhatOnlyTheAccountHas() async throws {
        let store = try await device()
        let remote = try await cloudRows()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await store.queueFullUpload(replacing: remote, at: now)

        let events = try await store.pendingEvents(limit: 10000)
        let byKey = Dictionary(events.map { ("\($0.entity) \($0.entityID)", $0) }) { first, _ in first }
        #expect(byKey.count == events.count, "one event per row")
        // The account's own account goes, as a tombstone the API accepts (a whole row, deleted).
        let tombstone = try #require(byKey["account \(cloudAccount.id.uuidString.lowercased())"])
        #expect(tombstone.operation == "delete")
        let deleted = try row(tombstone)
        #expect(deleted["deleted_at"] as? String == NameBasedID.isoMilliseconds(now))
        #expect(deleted["name"] as? String == "From the web")
        // Every local account, movement and goal goes up.
        for account in sample.accounts {
            #expect(byKey["account \(account.id.uuidString.lowercased())"]?.operation == "create")
        }
        for transaction in sample.transactions {
            #expect(byKey["transaction \(transaction.id.uuidString.lowercased())"] != nil)
        }
        for loan in sample.loans {
            for payment in loan.payments {
                #expect(byKey["loanPayment \(NameBasedID.loanPayment(loanID: loan.id, number: payment.number).uuidString.lowercased())"] !=
                    nil)
            }
        }
        // This iPhone's settings replace the account's, never deleted.
        let settings = try #require(byKey["settings settings"])
        #expect(settings.operation == "update")
        #expect(try row(settings)["principal"] as? String == sample.settings.currencies.principal)
    }

    @Test
    func aRowOnBothSidesGoesUpJustAfterTheAccountsCopy() async throws {
        let store = try await device()
        let account = try #require(sample.accounts.first)
        let id = account.id.uuidString.lowercased()
        let local = try #require(try await store.pendingEvents(limit: 10000).first { $0.entity == "account" && $0.entityID == id })
        var newer = try row(local)
        newer["name"] = "Renamed on the web"
        newer["updated_at"] = "2099-01-01T00:00:00.000Z"
        let remote = try [RemoteRow(entity: "account", row: JSONSerialization.data(withJSONObject: newer))]

        try await store.queueFullUpload(replacing: remote, at: .now)

        let event = try #require(try await store.pendingEvents(limit: 10000).first { $0.entity == "account" && $0.entityID == id })
        #expect(event.operation == "update")
        let sent = try row(event)
        #expect(sent["name"] as? String == account.name)
        #expect(sent["updated_at"] as? String == "2099-01-01T00:00:00.001Z")
    }
}
