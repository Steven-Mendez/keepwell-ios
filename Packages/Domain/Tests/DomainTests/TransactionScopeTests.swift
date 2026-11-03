import Foundation
import Testing
@testable import Domain

@Suite("Transaction scope")
struct TransactionScopeTests {
    private let checking = UUID()
    private let cash = UUID()
    private let card = UUID()

    @Test
    func allIncludesEverything() {
        #expect(TransactionScope.all.includes(Fixtures.transaction(amount: "5", account: checking)))
    }

    @Test
    func accountIncludesWhatLeavesAndWhatArrives() {
        let spent = Fixtures.transaction(amount: "5", account: checking, card: card)
        let withdrawal = Fixtures.transaction(.transfer, amount: "20", account: checking, destination: cash)
        let elsewhere = Fixtures.transaction(amount: "5", account: UUID())
        #expect(TransactionScope.account(checking).includes(spent))
        #expect(TransactionScope.account(checking).includes(withdrawal))
        #expect(TransactionScope.account(cash).includes(withdrawal))
        #expect(!TransactionScope.account(checking).includes(elsewhere))
    }
}
