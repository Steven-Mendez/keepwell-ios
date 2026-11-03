import Foundation
import Testing
@testable import Domain

@Suite("Currency conversion (rule 2)")
struct ConversionTests {
    private func cents(_ value: Decimal) -> Decimal {
        value.rounded(scale: 2)
    }

    @Test
    func secondCurrencyAmountConvertsWithStoredRate() {
        let lunch = Fixtures.transaction(amount: "250", currency: "NIO")
        #expect(cents(lunch.principalAmount) == Fixtures.decimal("6.83"))
        #expect(lunch.secondAmount == 250)
    }

    @Test
    func principalAmountConvertsToSecond() {
        let tool = Fixtures.transaction(amount: "200", currency: "USD")
        #expect(tool.principalAmount == 200)
        #expect(cents(tool.secondAmount) == Fixtures.decimal("7324.86"))
    }

    @Test
    func actualDebitWinsForPrincipalAndDrivesSecond() {
        // C$879 charged as $24.28 by the bank.
        let dinner = Fixtures.transaction(amount: "879", currency: "NIO", actualDebited: "24.28")
        #expect(dinner.principalAmount == Fixtures.decimal("24.28"))
        #expect(dinner.secondAmount == 879)
        #expect(dinner.bankRate.map { $0.rounded(scale: 2) } == Fixtures.decimal("36.20"))
    }

    @Test
    func actualDebitOnPrincipalPurchaseFeedsSecondAmount() {
        let purchase = Fixtures.transaction(amount: "20", currency: "USD", actualDebited: "20.42")
        #expect(purchase.principalAmount == Fixtures.decimal("20.42"))
        #expect(cents(purchase.secondAmount) == Fixtures.decimal("747.87"))
        #expect(purchase.bankRate == nil)
    }

    @Test
    func changingTheSettingsRateNeverRewritesHistory() throws {
        let old = Fixtures.transaction(amount: "366.243", currency: "NIO")
        _ = try ExchangeRate(principal: "USD", second: "NIO", rate: 40)
        #expect(old.principalAmount == 10)
    }

    @Test
    func singleCurrencyModeIsIdentity() {
        let movement = Fixtures.transaction(amount: "12.5", currency: "USD", rate: .single("USD"))
        #expect(movement.principalAmount == Fixtures.decimal("12.5"))
        #expect(movement.secondAmount == Fixtures.decimal("12.5"))
    }

    @Test
    func amountInPicksTheRequestedCurrency() {
        let withdrawal = Fixtures.transaction(.transfer, amount: "1200", currency: "NIO", actualDebited: "33.15")
        #expect(withdrawal.amount(in: "USD") == Fixtures.decimal("33.15"))
        #expect(withdrawal.amount(in: "NIO") == 1200)
    }

    @Test
    func confirmingFlipsOnlyTheStatus() {
        let planned = Fixtures.transaction(amount: "700", currency: "NIO", status: .planned)
        let confirmed = planned.confirmed()
        #expect(confirmed.isConfirmed)
        #expect(confirmed.with(status: .planned) == planned)
    }
}
