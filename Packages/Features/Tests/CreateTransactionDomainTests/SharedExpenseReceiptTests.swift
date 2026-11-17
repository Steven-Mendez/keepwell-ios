import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionDomain

@Suite("Shared expenses on the receipt")
struct SharedExpenseReceiptTests {
    private let ledger = SharedExpenseLedger()

    @Test
    func theReceiptsCategoryTotalIsThePersonsPart() throws {
        let saved = try DefaultSaveTransactionUseCase.receipt(
            of: ledger.shared, accounts: [ledger.account], movements: ledger.movements, principal: "USD", calendar: ledger.calendar,
            debts: ledger.debts,
        )
        #expect(saved.categoryMonthTotal == Money(30, "USD"))
        let gross = try DefaultSaveTransactionUseCase.receipt(
            of: ledger.shared, accounts: [ledger.account], movements: ledger.movements, principal: "USD", calendar: ledger.calendar,
        )
        #expect(gross.categoryMonthTotal == Money(90, "USD"))
    }
}
