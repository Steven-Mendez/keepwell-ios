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
}
