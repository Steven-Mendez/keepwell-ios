import Foundation
import Testing
@testable import OnboardingPresentation

@Suite("Onboarding currencies")
@MainActor
struct OnboardingCurrenciesTests {
    @Test
    func startsOnTheRegionCurrencyAloneWithCashIncluded() {
        let viewModel = OnboardingFactory.make()
        #expect(viewModel.currencyMode == .single)
        #expect(viewModel.principal == "USD")
        #expect(viewModel.second == nil)
        #expect(viewModel.canContinueFromCurrencies)
        #expect(viewModel.accounts.map(\.kind) == [.cash])
        #expect(viewModel.accounts.first?.currency == "USD")
        #expect(viewModel.principalLabel == "USD · US Dollar")
    }

    @Test
    func regionCurrencyBecomesTheMainOneAndUnknownCodesFallBackToUSD() {
        #expect(OnboardingFactory.make(regionCurrency: "EUR").principal == "EUR")
        #expect(OnboardingFactory.make(regionCurrency: "EUR").secondChoice == "USD")
        #expect(OnboardingFactory.make(regionCurrency: "XYZ").principal == "USD")
        #expect(OnboardingFactory.make(regionCurrency: nil).principal == "USD")
    }

    @Test
    func twoCurrenciesStartsWithACommonSecondAtRateOne() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        #expect(viewModel.second == "EUR")
        #expect(viewModel.rate == 1)
        #expect(viewModel.accounts.first?.currency == "USD")
        #expect(viewModel.rateSummary == "1 USD = 1 EUR")
        #expect(viewModel.currenciesSummary == "USD + EUR")
    }

    @Test
    func commonCurrenciesComeFirstWithoutTheMainOne() {
        let viewModel = OnboardingFactory.make()
        #expect(viewModel.secondCurrencyOptions == ["EUR", "GBP", "MXN", "CAD", "JPY", "CHF", "BRL"])
        #expect(viewModel.principalOptions.first == "USD")
        #expect(!viewModel.secondCurrencyOptions.contains("NIO"))
    }

    @Test
    func choosingACurrencyResetsTheRate() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.rateText = "36.6243"
        viewModel.selectSecond("MXN")
        #expect(viewModel.rateText == "1.0000")
        #expect(viewModel.accounts.first?.currency == "USD")
    }

    @Test
    func backToOneCurrencyHidesTheRateAndMovesCashToPrincipal() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.selectSecond("MXN")
        viewModel.setCurrencyMode(.single)
        #expect(viewModel.rateSummary == nil)
        #expect(viewModel.currenciesSummary == "USD")
        #expect(viewModel.accounts.first?.currency == "USD")
        #expect(viewModel.canContinueFromCurrencies)
        viewModel.setCurrencyMode(.dual)
        #expect(viewModel.second == "MXN")
    }

    @Test
    func invalidRateBlocksContinuing() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.rateText = "0"
        #expect(!viewModel.canContinueFromCurrencies)
        viewModel.rateText = "36,5"
        #expect(viewModel.rate == Decimal(string: "36.5"))
    }

    @Test
    func searchedCurrencyBecomesAnOption() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.selectSecond("NIO")
        #expect(viewModel.second == "NIO")
        #expect(viewModel.secondCurrencyOptions.last == "NIO")
    }

    @Test
    func mainCurrencyCanBeAnyCode() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.selectPrincipal("NIO")
        #expect(viewModel.principal == "NIO")
        #expect(viewModel.second == "EUR")
        #expect(viewModel.accounts.first?.currency == "NIO")
        #expect(!viewModel.secondCurrencyOptions.contains("NIO"))
        #expect(viewModel.secondCurrencyOptions.contains("USD"))
    }

    @Test
    func secondCannotBeTheMainCurrency() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.selectSecond("USD")
        #expect(viewModel.second == "EUR")
    }

    @Test
    func choosingTheSecondAsMainSwapsThem() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.selectSecond("NIO")
        viewModel.rateText = "36.6243"
        viewModel.selectPrincipal("NIO")
        #expect(viewModel.principal == "NIO")
        #expect(viewModel.second == "USD")
        #expect(viewModel.rateText == "0.027304")
    }

    @Test
    func swappingInvertsTheRateAndKeepsBankAccountsInTheirCurrency() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.selectSecond("NIO")
        viewModel.rateText = "36.6243"
        var bank = viewModel.newAccount(.bank)
        bank.name = "Savings"
        viewModel.save(bank)
        viewModel.swapCurrencies()
        #expect(viewModel.principal == "NIO")
        #expect(viewModel.second == "USD")
        #expect(viewModel.rateSummary == "1 NIO = 0.027304 USD")
        #expect(viewModel.accounts.first { $0.kind == .bank }?.currency == "USD")
        #expect(viewModel.accounts.first { $0.kind == .cash }?.currency == "USD")
        viewModel.swapCurrencies()
        #expect(viewModel.principal == "USD")
        #expect(viewModel.second == "NIO")
    }

    @Test
    func swappingAtRateOneKeepsTheDefault() {
        let viewModel = OnboardingFactory.make()
        viewModel.setCurrencyMode(.dual)
        viewModel.swapCurrencies()
        #expect(viewModel.principal == "EUR")
        #expect(viewModel.second == "USD")
        #expect(viewModel.rateText == "1.0000")
    }

    @Test
    func cashStaysInTheMainCurrencyWhenASecondIsAdded() {
        let viewModel = OnboardingFactory.usdAndNIO()
        #expect(viewModel.accounts.map(\.currency) == ["USD"])
    }

    @Test
    func aSecondCashAccountTakesTheCurrencyWithoutCash() {
        let viewModel = OnboardingFactory.usdAndNIO()
        let cash = viewModel.newAccount(.cash)
        #expect(cash.currency == "NIO")
        #expect(viewModel.cashCurrencyOptions(for: cash) == ["NIO"])
        viewModel.save(cash)
        #expect(viewModel.cashCurrencyOptions(for: viewModel.accounts[0]) == ["USD"])
        // Every currency has its cash, so the tile opens the existing one.
        #expect(viewModel.newAccount(.cash).id == viewModel.accounts[0].id)
    }

    @Test
    func aLoneCashAccountCanMoveToEitherCurrency() {
        let viewModel = OnboardingFactory.usdAndNIO()
        #expect(viewModel.cashCurrencyOptions(for: viewModel.accounts[0]) == ["USD", "NIO"])
    }

    @Test
    func cashCanBeRemoved() {
        let viewModel = OnboardingFactory.make()
        viewModel.removeAccount(id: viewModel.accounts[0].id)
        #expect(viewModel.accounts.isEmpty)
    }

    @Test
    func goingBackToOneCurrencyDropsTheCashInTheOtherOne() {
        let viewModel = OnboardingFactory.usdAndNIO()
        viewModel.save(viewModel.newAccount(.cash))
        viewModel.setCurrencyMode(.single)
        #expect(viewModel.accounts.map(\.currency) == ["USD"])
    }

    @Test
    func cashInTwoCurrenciesIsSavedWithItsCurrencyInTheName() async {
        let complete = CompleteOnboardingStub()
        let viewModel = OnboardingFactory.make(complete: complete)
        viewModel.setCurrencyMode(.dual)
        viewModel.selectSecond("NIO")
        viewModel.save(viewModel.newAccount(.cash))
        await viewModel.skipNotifications()
        #expect(complete.received.draft?.accounts.map(\.name) == ["Cash USD", "Cash NIO"])
    }
}
