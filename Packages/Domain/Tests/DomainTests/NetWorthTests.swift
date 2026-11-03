import Foundation
import Testing
@testable import Domain

@Suite("Net worth (rule 6)")
struct NetWorthTests {
    @Test
    func sumsBalancesConvertedToPrincipal() throws {
        let settings = try CurrencySettings(second: "NIO", rate: Fixtures.decimal("36.6243"))
        let balances = [
            Money(Fixtures.decimal("9306.78"), "USD"),
            Money(Fixtures.decimal("1668.65"), "USD"),
            Money(8420, "NIO"),
            Money(Fixtures.decimal("-941.30"), "NIO"),
            Money(Fixtures.decimal("-16.79"), "USD"),
            Money(Fixtures.decimal("-197.02"), "NIO"),
        ]
        let total = try NetWorth.total(of: balances, settings: settings)
        #expect(total.currency == "USD")
        #expect(total.amount.rounded(scale: 2) == Fixtures.decimal("11157.46"))
        let inSecond = try #require(NetWorth.inSecondCurrency(total, settings: settings))
        #expect(inSecond.amount.rounded(scale: 0) == 408_634)
    }

    @Test
    func unknownCurrencyThrows() throws {
        let settings = try CurrencySettings(second: "NIO", rate: 36)
        #expect(throws: DomainError.currencyMismatch("EUR", "USD")) {
            try NetWorth.total(of: [Money(1, "EUR")], settings: settings)
        }
    }

    @Test
    func singleCurrencyHasNoSecondTotal() throws {
        let settings = try CurrencySettings()
        #expect(NetWorth.inSecondCurrency(Money(5, "USD"), settings: settings) == nil)
    }
}
