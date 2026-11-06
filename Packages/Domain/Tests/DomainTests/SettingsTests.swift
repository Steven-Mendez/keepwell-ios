import Foundation
import Testing
@testable import Domain

@Suite("Settings")
struct SettingsTests {
    @Test
    func defaultsToUSDWithRateOne() throws {
        let settings = try CurrencySettings()
        #expect(settings.principal == "USD")
        #expect(settings.second == nil)
        #expect(settings.rate == 1)
        #expect(settings.exchangeRate == .single("USD"))
    }

    @Test
    func secondCurrencyRateIsStoredOnNewTransactions() throws {
        let settings = try CurrencySettings(second: "NIO", rate: Fixtures.decimal("36.6243"))
        #expect(settings.exchangeRate == Fixtures.usdNio)
    }

    @Test
    func rejectsNonPositiveRate() {
        #expect(throws: DomainError.invalidExchangeRate) { try CurrencySettings(second: "NIO", rate: 0) }
    }

    @Test
    func secondEqualToPrincipalMeansSingleCurrency() throws {
        let settings = try CurrencySettings(principal: "USD", second: "USD", rate: 5)
        #expect(settings.second == nil)
        #expect(settings.rate == 1)
    }

    @Test
    func appSettingsDefaultsMatchDesign() throws {
        let settings = try Settings(currencies: CurrencySettings())
        #expect(settings.unlockMethod == .biometrics)
        #expect(settings.relockAfter == 60)
        #expect(settings.hidesAmountsInAppSwitcher)
        #expect(settings.isICloudBackupEnabled)
        #expect(settings.paymentReminderDaysBefore == 3)
    }

    @Test
    func swappingMakesTheSecondCurrencyMainAndTurnsTheRateAround() throws {
        let currencies = try CurrencySettings(principal: "USD", second: "NIO", rate: Fixtures.decimal("36.6243"))
        let swapped = try #require(currencies.swapped())
        #expect(swapped.principal == "NIO")
        #expect(swapped.second == "USD")
        #expect(swapped.rate.rounded(scale: 6) == Fixtures.decimal("0.027304"))
        let back = try #require(swapped.swapped())
        #expect(back.principal == "USD")
        #expect(back.rate.rounded(scale: 6) == Fixtures.decimal("36.6243"))
    }

    @Test
    func aSingleCurrencyHasNothingToSwap() throws {
        #expect(try CurrencySettings(principal: "USD").swapped() == nil)
    }

    /// Past movements keep their own rate, so they convert the same after the swap.
    @Test
    func pastMovementsConvertTheSameAfterSwapping() throws {
        let rate = try ExchangeRate(principal: "USD", second: "NIO", rate: Fixtures.decimal("36.6243"))
        let lunch = Transaction(
            date: .now, description: "Lunch", kind: .expense, categoryID: "restaurants", amount: 250, currency: "NIO",
            accountID: UUID(), actualDebitedPrincipal: Fixtures.decimal("6.83"), exchangeRate: rate,
        )
        #expect(lunch.amount(in: "USD") == Fixtures.decimal("6.83"))
        #expect(lunch.amount(in: "NIO") == 250)
    }
}
