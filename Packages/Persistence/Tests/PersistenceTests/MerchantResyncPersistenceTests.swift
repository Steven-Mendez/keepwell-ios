import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// The store's side of the one-time merchant download after an upgrade, of committing with
/// tombstoned merchants, and of deleting a category in a merchant commit.
@Suite("Merchant links after an upgrade")
struct MerchantResyncPersistenceTests {
    private let sample = SampleData.standard
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let subwayID = UUID(uuidString: "66666666-6666-4666-8666-666666666666") ?? UUID()
    private let uberEatsID = UUID(uuidString: "77777777-7777-4777-8777-777777777777") ?? UUID()

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private var subway: Merchant {
        Merchant(id: subwayID, name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    }

    private func movement(_ id: UUID = UUID(), description: String = "Subway", merchantID: UUID? = nil) throws -> Transaction {
        try Transaction(
            id: id, date: now, description: description, kind: .expense, categoryID: "restaurants", amount: 12,
            currency: "USD", accountID: #require(sample.accounts.first?.id), exchangeRate: sample.settings.currencies.exchangeRate,
            merchantID: merchantID,
        )
    }

    private func payload(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    /// The account's row of a record this device has: its own wire row with the account's links.
    private func remote(of event: OutboxEvent, links: [String: Any]) throws -> Data {
        var row = try payload(event)
        for (key, value) in links {
            row[key] = value
        }
        return try JSONSerialization.data(withJSONObject: row)
    }

    private func sendAll(_ phone: SwiftDataStore) async throws {
        try await phone.removeEvents(ids: phone.pendingEvents(limit: 1000).map(\.id))
    }

    @Test
    func aPendingEditKeepsItsChangeAndGetsTheLinksItNeverHad() async throws {
        let phone = try store()
        let id = UUID()
        // Pulled by the old build: no links stored.
        try await phone.save(movement(id))
        let synced = try #require(try await phone.pendingEvents(limit: 10).last)
        try await sendAll(phone)
        // Edited by this build before the download: the edit waits with null links.
        try await phone.save(movement(id, description: "Subway centro"))
        #expect(await phone.pendingCount() == 1)
        let account = try remote(of: synced, links: [
            "merchant_id": subwayID.uuidString.lowercased(), "via_merchant_id": uberEatsID.uuidString.lowercased(),
        ])

        #expect(try await phone.fillMissingMerchantLinks(entity: "transaction", row: account))

        let stored = try #require(try await phone.fetchTransactions(in: nil).first)
        #expect(stored.description == "Subway centro")
        #expect(stored.merchantID == subwayID)
        #expect(stored.viaMerchantID == uberEatsID)
        let events = try await phone.pendingEvents(limit: 10)
        #expect(events.count == 1)
        let sent = try payload(#require(events.first))
        #expect(sent["description"] as? String == "Subway centro")
        #expect(sent["merchant_id"] as? String == subwayID.uuidString.lowercased())
        #expect(sent["via_merchant_id"] as? String == uberEatsID.uuidString.lowercased())
        // Nothing left to fill.
        #expect(try await !phone.fillMissingMerchantLinks(entity: "transaction", row: account))
    }

    @Test
    func aLinkSetHereStaysAndATombstoneIsLeftAlone() async throws {
        let phone = try store()
        let id = UUID()
        try await phone.save(movement(id, merchantID: uberEatsID))
        let event = try #require(try await phone.pendingEvents(limit: 10).last)
        let account = try remote(of: event, links: ["merchant_id": subwayID.uuidString.lowercased()])
        #expect(try await !phone.fillMissingMerchantLinks(entity: "transaction", row: account))
        #expect(try await phone.fetchTransactions(in: nil).first?.merchantID == uberEatsID)
        // The account's business is this device's platform: never both.
        #expect(try await phone.fetchTransactions(in: nil).first?.viaMerchantID == nil)

        try await phone.deleteTransaction(id: id)
        #expect(try await !phone.fillMissingMerchantLinks(entity: "transaction", row: account))
    }

    @Test
    func aRuleWithAPendingEditGetsItsMerchantAndARowWithoutOneIsRead() async throws {
        let phone = try store()
        let rule = CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense)
        try await phone.save(rule)
        let event = try #require(try await phone.pendingEvents(limit: 10).last)
        let account = try remote(of: event, links: ["merchant_id": subwayID.uuidString.lowercased()])
        #expect(try await phone.fillMissingMerchantLinks(entity: "categorizationRule", row: account))
        #expect(try await phone.fetchCategorizationRules().first?.merchantID == subwayID)
        #expect(try payload(#require(try await phone.pendingEvents(limit: 10).last))["merchant_id"] as? String
            == subwayID.uuidString.lowercased())
        await #expect(throws: DomainError.self) {
            try await phone.fillMissingMerchantLinks(entity: "categorizationRule", row: remote(of: event, links: ["merchant_id": "x"]))
        }
    }

    /// Without a pending change the download is a plain apply: the account's links come in whole.
    @Test
    func aSyncedRowTakesTheAccountsLinks() async throws {
        let phone = try store()
        let id = UUID()
        try await phone.save(movement(id))
        let event = try #require(try await phone.pendingEvents(limit: 10).last)
        try await sendAll(phone)
        var row = try payload(event)
        row["merchant_id"] = subwayID.uuidString.lowercased()
        #expect(try await phone.applyRemote(entity: "transaction", row: JSONSerialization.data(withJSONObject: row)))
        #expect(try await phone.fetchTransactions(in: nil).first?.merchantID == subwayID)
        #expect(await phone.pendingCount() == 0)
    }

    // MARK: Tombstones

    @Test
    func aMerchantDeletedByAPullIsNotBroughtBack() async throws {
        let phone = try store()
        try await phone.save(subway)
        let event = try #require(try await phone.pendingEvents(limit: 10).last)
        try await sendAll(phone)
        var deleted = try payload(event)
        deleted["deleted_at"] = "2030-01-01T00:00:00.000Z"
        deleted["updated_at"] = "2030-01-01T00:00:00.000Z"
        try await phone.applyRemote(entity: "merchant", row: JSONSerialization.data(withJSONObject: deleted))
        #expect(try await phone.fetchMerchants().isEmpty)

        let renamed = Merchant(id: subwayID, name: "Subway Centro", domain: "subway.com")
        try await phone.commit(MerchantChanges(transactions: [movement(merchantID: subwayID)], savedMerchants: [renamed]))
        #expect(try await phone.fetchMerchants().isEmpty)
        #expect(try await phone.deletedMerchantIDs() == [subwayID])
        #expect(try await !phone.pendingEvents(limit: 10).contains { $0.entity == "merchant" })
        await #expect(throws: DomainError.notFound(subwayID)) {
            try await phone.save(renamed)
        }
        #expect(try await phone.fetchMerchants().isEmpty)
    }

    // MARK: Deleting a category

    @Test
    func aCommitDeletesTheCategoryInTheSameSave() async throws {
        let phone = try store()
        try await phone.save(subway)
        let moved = try movement().with(categoryID: TransactionCategory.otherExpenseID)
        await #expect(throws: DomainError.notFound(uberEatsID)) {
            try await phone.commit(MerchantChanges(
                transactions: [moved], deletedMerchantIDs: [uberEatsID], deletedCategoryIDs: ["restaurants"],
            ))
        }
        #expect(try await phone.fetchCategories().contains { $0.id == "restaurants" })

        try await phone.commit(MerchantChanges(
            transactions: [moved], savedMerchants: [subway.with(defaultCategoryID: nil)], deletedCategoryIDs: ["restaurants"],
        ))
        #expect(try await !phone.fetchCategories().contains { $0.id == "restaurants" })
        #expect(try await phone.fetchMerchants().first?.defaultCategoryID == nil)
        let deletes = try await phone.pendingEvents(limit: 100).filter { $0.entity == "category" && $0.operation == "delete" }
        #expect(deletes.map(\.entityID) == ["restaurants"])
    }
}
