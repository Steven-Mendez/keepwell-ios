import Foundation
import Testing
@testable import Domain

@Suite("Money")
struct MoneyTests {
    @Test
    func addsSameCurrency() throws {
        let total = try Money(10.25, "USD").adding(Money(4.75, "USD"))
        #expect(total == Money(15, "USD"))
    }

    @Test
    func refusesToSumDifferentCurrencies() {
        #expect(throws: DomainError.currencyMismatch("USD", "NIO")) {
            try Money(10, "USD").adding(Money(366, "NIO"))
        }
    }

    @Test
    func subtractsAndNegates() throws {
        #expect(try Money(10, "NIO").subtracting(Money(12.5, "NIO")) == Money(-2.5, "NIO"))
        #expect(Money(3, "USD").negated == Money(-3, "USD"))
    }

    @Test
    func normalizesCurrencyCodes() throws {
        #expect(try Money.normalizedCurrency(" nio ") == "NIO")
        #expect(throws: DomainError.invalidCurrency("XYZ1")) { try Money.normalizedCurrency("XYZ1") }
    }
}

@Suite("Exchange rate")
struct ExchangeRateTests {
    private let rate = try? ExchangeRate(principal: "USD", second: "NIO", rate: Decimal(string: "36.6243") ?? 1)

    @Test
    func rejectsNonPositiveRates() {
        #expect(throws: DomainError.invalidExchangeRate) { try ExchangeRate(principal: "USD", second: "NIO", rate: 0) }
        #expect(throws: DomainError.invalidExchangeRate) { try ExchangeRate(principal: "USD", second: "NIO", rate: -1) }
    }

    @Test
    func convertsBothWays() throws {
        let rate = try #require(rate)
        let cash = try rate.convert(Money(8420, "NIO"), to: "USD")
        #expect(cash.currency == "USD")
        #expect(cash.amount.rounded(scale: 2) == Decimal(string: "229.90"))
        #expect(try rate.convert(Money(100, "USD"), to: "NIO") == Money(Decimal(string: "3662.43") ?? 0, "NIO"))
    }

    @Test
    func sameCurrencyIsIdentity() throws {
        let rate = try #require(rate)
        #expect(try rate.convert(Money(5, "USD"), to: "USD") == Money(5, "USD"))
    }

    @Test
    func currenciesOutsideTheRateThrow() throws {
        let rate = try #require(rate)
        #expect(throws: DomainError.currencyMismatch("EUR", "USD")) { try rate.convert(Money(5, "EUR"), to: "USD") }
    }

    @Test
    func singleCurrencyModeHasRateOne() {
        let single = ExchangeRate.single("USD")
        #expect(single.rate == 1)
        #expect(!single.hasSecondCurrency)
    }
}
