import Foundation
import Testing
@testable import Domain

@Suite("Cash reconciliation")
struct CashReconciliationTests {
    private let cash = Account(name: "Wallet", kind: .cash, openingBalances: [Money(0, "NIO")], openingDate: .now)

    private func adjust(balance: Decimal, counted: Decimal) throws -> Transaction? {
        try CashReconciliation.adjustment(
            for: cash, balance: Money(balance, "NIO"), counted: counted, date: .now, exchangeRate: Fixtures.usdNio,
        )
    }

    @Test
    func shortfallBecomesAdjustmentExpense() throws {
        let adjustment = try #require(try adjust(balance: 8420, counted: 8000))
        #expect(adjustment.kind == .expense)
        #expect(adjustment.amount == 420)
        #expect(adjustment.currency == "NIO")
        #expect(adjustment.categoryID == TransactionCategory.otherExpenseID)
        #expect(adjustment.accountID == cash.id)
    }

    @Test
    func surplusBecomesIncome() throws {
        let adjustment = try #require(try adjust(balance: 100, counted: 150))
        #expect(adjustment.kind == .income)
        #expect(adjustment.amount == 50)
    }

    @Test
    func matchingCountNeedsNoAdjustment() throws {
        #expect(try adjust(balance: 100, counted: 100) == nil)
    }

    @Test
    func negativeCountIsRejected() {
        #expect(throws: DomainError.invalidAmount) { try adjust(balance: 100, counted: -1) }
    }
}
