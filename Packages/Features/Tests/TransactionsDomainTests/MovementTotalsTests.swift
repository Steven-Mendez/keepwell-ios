import Domain
import Foundation
import Testing
@testable import TransactionsDomain

@Suite("Movement totals")
struct MovementTotalsTests {
    private func movement(
        _ kind: TransactionKind,
        _ amount: Decimal,
        currency: String = "USD",
        rate: ExchangeRate = .single("USD"),
        status: TransactionStatus = .confirmed,
    ) -> Transaction {
        Transaction(
            date: .now, status: status, description: "x", kind: kind, categoryID: nil, amount: amount,
            currency: currency, accountID: UUID(), exchangeRate: rate,
        )
    }

    @Test
    func countsConfirmedIncomeAndSpendingOnly() {
        let totals = MovementTotals(of: [
            movement(.income, 500),
            movement(.expense, 120),
            movement(.expense, 30),
            movement(.transfer, 1000),
            movement(.expense, 999, status: .planned),
            movement(.income, 888, status: .planned),
        ], currency: "USD")
        #expect(totals.count == 6)
        #expect(totals.moneyIn == 500)
        #expect(totals.moneyOut == 150)
        #expect(totals.net == 350)
    }

    @Test
    func emptyListIsAllZero() {
        let totals = MovementTotals(of: [], currency: "USD")
        #expect(totals.count < 1)
        #expect(totals.net == 0)
    }

    @Test
    func expressesEachMovementInTheRequestedCurrencyWithoutMixing() throws {
        let rate = try ExchangeRate(principal: "USD", second: "NIO", rate: 36)
        let inNIO = movement(.expense, 360, currency: "NIO", rate: rate)
        let inUSD = movement(.expense, 10, rate: rate)
        #expect(MovementTotals(of: [inNIO, inUSD], currency: "USD").moneyOut == 20)
        #expect(MovementTotals(of: [inNIO, inUSD], currency: "NIO").moneyOut == 720)
    }
}
