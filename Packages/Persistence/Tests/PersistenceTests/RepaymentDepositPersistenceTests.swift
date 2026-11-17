import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// A repayment's deposit link in storage and on the wire: `transaction_id` always sent (null for
/// none), a pulled row without the key keeps the stored link and null clears it, repayments already
/// stored aren't sent again, and the deposits of deleted debts and repayments stay known.
@Suite("Repayment deposits in storage")
struct RepaymentDepositPersistenceTests {
    private let sample = SampleData.standard
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let debtID = UUID(uuidString: "55555555-5555-4555-8555-555555555555") ?? UUID()
    private let movementID = UUID(uuidString: "44444444-4444-4444-8444-444444444444") ?? UUID()

    private func store() throws -> SwiftDataStore {
        try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
    }

    private func row(_ event: OutboxEvent) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: event.payload) as? [String: Any])
    }

    private func debt(_ repayments: [DebtRepayment] = []) -> PersonalDebt {
        PersonalDebt(
            id: debtID, person: "Ana", direction: .theyOweMe, amount: Money(300, "NIO"), date: now, repayments: repayments,
        )
    }

    private func fixtureEvents(_ key: String) throws -> [(name: String, entity: String, payload: [String: Any])] {
        let url = try #require(Bundle.module.url(forResource: "sync", withExtension: "json", subdirectory: "Fixtures"))
        let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(file[key] as? [[String: Any]]).compactMap { item in
            guard let name = item["name"] as? String, name.contains("debt repayment"),
                  let event = item["event"] as? [String: Any], let entity = event["entity"] as? String,
                  let payload = event["payload"] as? [String: Any] else { return nil }
            return (name, entity, payload)
        }
    }

    @Test
    func readsTheFixtureRepaymentsAndRefusesALinkThatIsntAnID() async throws {
        let valid = try fixtureEvents("valid")
        #expect(valid.count == 3)
        for item in valid {
            let store = try store()
            try await store.save(debt())
            #expect(try await store.applyRemote(entity: item.entity, row: JSONSerialization.data(withJSONObject: item.payload)))
            let repayment = try #require(await store.fetchPersonalDebts().first?.repayments.first, "\(item.name)")
            let sent = item.payload["transaction_id"] as? String
            #expect(repayment.transactionID == sent.flatMap(UUID.init(uuidString:)), "\(item.name)")
            #expect(BackupColumns.problem(entity: item.entity, row: item.payload) == nil, "\(item.name)")
        }
        let invalid = try fixtureEvents("invalid")
        #expect(invalid.count == 1)
        for item in invalid {
            let store = try store()
            await #expect(throws: DomainError.self) {
                try await store.applyRemote(entity: item.entity, row: JSONSerialization.data(withJSONObject: item.payload))
            }
            #expect(BackupColumns.problem(entity: item.entity, row: item.payload) == "transaction_id")
        }
    }

    @Test
    func sendsTheDepositLinkNullForNoneAndDoesntResendStoredRepayments() async throws {
        let phone = try store()
        let deposited = DebtRepayment(amount: 20, date: now, transactionID: movementID)
        let recorded = DebtRepayment(amount: 10, date: now)
        try await phone.save(debt([deposited, recorded]))
        let rows = try await phone.pendingEvents().filter { $0.entity == "personalDebtRepayment" }.map(row)
        #expect(rows.map { $0["transaction_id"] as? String } == [movementID.uuidString.lowercased(), nil])
        #expect(rows.last?["transaction_id"] is NSNull)
        #expect(try await phone.fetchPersonalDebts().first?.repayments.map(\.transactionID) == [movementID, nil])
        // Saving the debt again (say, a new note) doesn't send its repayments again.
        try await phone.removeEvents(ids: phone.pendingEvents().map(\.id))
        try await phone.save(debt([deposited, recorded]))
        #expect(try await phone.pendingEvents().allSatisfy { $0.entity == "personalDebt" })
    }

    @Test
    func aPulledRowWithoutTheKeyKeepsTheLinkAndNullClearsIt() async throws {
        let phone = try store()
        let repayment = DebtRepayment(amount: 20, date: now, transactionID: movementID)
        try await phone.save(debt([repayment]))
        var row: [String: Any] = [
            "id": repayment.id.uuidString.lowercased(), "debt_id": debtID.uuidString.lowercased(), "amount": "25",
            "date": "2027-01-15T08:00:00.000Z", "created_at": "2027-01-15T08:00:00.000Z", "updated_at": "2027-01-15T09:00:00.000Z",
            "deleted_at": NSNull(),
        ]
        #expect(try await phone.applyRemote(entity: "personalDebtRepayment", row: JSONSerialization.data(withJSONObject: row)))
        let kept = try #require(await phone.fetchPersonalDebts().first?.repayments.first)
        #expect(kept.amount == 25)
        #expect(kept.transactionID == movementID)
        row["transaction_id"] = NSNull()
        #expect(try await phone.applyRemote(entity: "personalDebtRepayment", row: JSONSerialization.data(withJSONObject: row)))
        #expect(try await phone.fetchPersonalDebts().first?.repayments.first?.transactionID == nil)
    }

    @Test
    func savesTheDepositWithTheDebtAndDeletesItWithTheRepayment() async throws {
        let phone = try store()
        try await phone.save(debt())
        let account = try #require(sample.accounts.first)
        try await phone.save(account)
        let income = Transaction(
            id: movementID, date: now, description: "Ana", kind: .income, categoryID: "refunds", amount: 300, currency: "NIO",
            accountID: account.id, exchangeRate: sample.settings.currencies.exchangeRate,
        )
        let repaid = try debt().repaying(300, on: now, transactionID: movementID)
        try await phone.save(repaid, recording: income)
        #expect(try await phone.fetchTransactions(in: nil).contains { $0.id == movementID })
        #expect(try await phone.fetchPersonalDebts().first?.isSettled == true)
        let repayment = try #require(repaid.repayments.first)
        let (open, removed) = try repaid.removingRepayment(id: repayment.id)
        try await phone.save(open, deletingTransaction: removed.transactionID)
        #expect(try await !phone.fetchTransactions(in: nil).contains { $0.id == movementID })
        #expect(try await phone.fetchPersonalDebts().first?.repayments.isEmpty == true)
        // The removed repayment's tombstone keeps its deposit known.
        #expect(try await phone.fetchRepaymentDepositIDs() == [movementID])
    }

    @Test
    func theDepositsOfDeletedDebtsAreStillKnown() async throws {
        let phone = try store()
        try await phone.save(debt([DebtRepayment(amount: 20, date: now, transactionID: movementID), DebtRepayment(amount: 10, date: now)]))
        #expect(try await phone.fetchRepaymentDepositIDs() == [movementID])
        try await phone.deletePersonalDebt(id: debtID)
        #expect(try await phone.fetchPersonalDebts().isEmpty)
        #expect(try await phone.fetchRepaymentDepositIDs() == [movementID])
    }
}
