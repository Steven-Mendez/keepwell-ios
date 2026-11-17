import Domain
import DomainSamples
import Foundation
import Testing
@testable import TransactionsDomain

/// "Your share: C$300 of C$900 · Split with Ana, Luis" on a split expense's detail.
@Suite("A split expense's share")
struct SplitShareLineTests {
    @Test
    func aSplitExpenseShowsThePersonsPartAndWhoElseOwes() throws {
        let ledger = SharedExpenseLedger()
        let list = TransactionList(
            settings: .initial, transactions: ledger.movements, accounts: [ledger.account], cards: [], categories: [],
            personalDebts: ledger.debts,
        )
        let split = try #require(list.split(of: ledger.shared))
        #expect(split.share == Money(30, "USD"))
        #expect(split.total == Money(90, "USD"))
        #expect(split.people == ["Ana", "Luis"])
        #expect(list.split(of: ledger.groceries) == nil)
        #expect(list.split(of: ledger.deposit) == nil)
    }
}
