import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Settings")
struct SettingsUseCasesTests {
    private let sample = SampleData.standard

    @Test
    func changingTheRateKeepsBothCurrencies() async throws {
        let store = InMemoryStore(sample: sample)
        let updated = try await DefaultUpdateSettingsUseCase(settings: store).execute { settings throws(DomainError) in
            try settings.setRate(Decimal(string: "37.1") ?? 0)
        }
        #expect(updated.currencies.principal == sample.settings.currencies.principal)
        #expect(updated.currencies.second == sample.settings.currencies.second)
        #expect(updated.currencies.rate == Decimal(string: "37.1"))
        #expect(await store.load() == updated)
    }

    @Test
    func swappingCurrenciesIsSaved() async throws {
        let store = InMemoryStore(sample: sample)
        let updated = try await DefaultUpdateSettingsUseCase(settings: store).execute { settings throws(DomainError) in
            try settings.swapCurrencies()
        }
        #expect(updated.currencies.principal == sample.settings.currencies.second)
        #expect(updated.currencies.second == sample.settings.currencies.principal)
        #expect(await store.load() == updated)
    }

    @Test
    func aZeroRateIsRefusedAndNothingIsSaved() async throws {
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.invalidExchangeRate) {
            _ = try await DefaultUpdateSettingsUseCase(settings: store).execute { settings throws(DomainError) in
                try settings.setRate(0)
            }
        }
        #expect(await store.load() == sample.settings)
    }

    @Test
    func overviewCountsCategoriesAndMethods() async throws {
        let store = InMemoryStore(sample: sample)
        let overview = try await DefaultGetSettingsOverviewUseCase(
            settings: store, categories: store, cards: store, accounts: store, transactions: store, rules: store,
        ).execute()
        #expect(overview.expenseCategoryCount == sample.categories.count { $0.kind == .expense })
        #expect(overview.incomeCategoryCount == sample.categories.count { $0.kind == .income })
        #expect(overview.paymentMethodCount == sample.cards.count)
    }

    @Test
    func exportHasOneRowPerMovementAfterTheHeader() async throws {
        let store = InMemoryStore(sample: sample)
        let csv = try await DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store)
            .execute()
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.first == Substring(DefaultExportTransactionsUseCase.header.joined(separator: ",")))
        #expect(lines.count == sample.transactions.count + 1)
    }

    @Test
    func exportQuotesFieldsWithCommasAndQuotes() {
        #expect(DefaultExportTransactionsUseCase.escaped("Lunch") == "Lunch")
        #expect(DefaultExportTransactionsUseCase.escaped("Rice, beans") == "\"Rice, beans\"")
        #expect(DefaultExportTransactionsUseCase.escaped("The \"good\" one") == "\"The \"\"good\"\" one\"")
    }
}

@Suite("Settings lock profile")
struct SettingsLockProfileTests {
    @Test
    func theOverviewReportsThePasscodeAndName() async throws {
        let store = InMemoryStore(sample: .standard)
        let lock = try InMemoryPasscodeStore(passcode: Passcode("482915"), name: "Steven")
        let overview = try await DefaultGetSettingsOverviewUseCase(
            settings: store, categories: store, cards: store, accounts: store, transactions: store, rules: store,
            passcodes: lock, profile: lock,
        ).execute()
        #expect(overview.hasPasscode)
        #expect(overview.preferredName == "Steven")
    }

    @Test
    func turningThePasscodeOffRemovesIt() async throws {
        let lock = try InMemoryPasscodeStore(passcode: Passcode("482915"))
        await DefaultRemovePasscodeUseCase(passcodes: lock).execute()
        #expect(await !lock.hasPasscode())
    }

    @Test
    func theNameIsTrimmedAndABlankOneIsForgotten() async {
        let lock = InMemoryPasscodeStore()
        await DefaultSetPreferredNameUseCase(profile: lock).execute("  Steven  ")
        #expect(await lock.preferredName() == "Steven")
        await DefaultSetPreferredNameUseCase(profile: lock).execute("   ")
        #expect(await lock.preferredName() == nil)
    }

    @Test
    func erasingAllDataEmptiesThisDevice() async throws {
        let store = InMemoryStore(sample: .standard)
        try await DefaultEraseAllDataUseCase(eraser: store).execute()
        #expect(await store.fetchTransactions(in: nil).isEmpty)
        #expect(await store.fetchAccounts().isEmpty)
    }
}

@Suite("Settings currencies")
struct SettingsCurrencyChangeTests {
    private func settings(second: String? = "NIO") throws -> Settings {
        try Settings(currencies: CurrencySettings(principal: "USD", second: second, rate: 36), hasCompletedOnboarding: true)
    }

    private func overview(_ store: InMemoryStore) async throws -> SettingsOverview {
        try await DefaultGetSettingsOverviewUseCase(
            settings: store, categories: store, cards: store, accounts: store, transactions: store, rules: store,
        ).execute()
    }

    @Test
    func theOverviewCountsRulesAndLocksCurrenciesInUse() async throws {
        let sample = SampleData.standard
        let used = try await overview(InMemoryStore(sample: sample))
        #expect(used.categorizationRuleCount == sample.categorizationRules.count)
        #expect(!used.canChangeMainCurrency)
        #expect(!used.canChangeSecondCurrency)

        let empty = try await overview(InMemoryStore(settings: settings()))
        #expect(empty.canChangeMainCurrency)
        #expect(empty.canChangeSecondCurrency)
    }

    @Test
    func theMainCurrencyChangesOnlyOnAnEmptyLedger() async throws {
        let empty = try InMemoryStore(settings: settings())
        let change = DefaultChangeCurrenciesUseCase(settings: empty, accounts: empty, transactions: empty)
        try await change.execute(.main("EUR"))
        let saved = await empty.load()?.currencies
        #expect(saved?.principal == "EUR")
        #expect(saved?.second == "NIO")
        #expect(saved?.rate == 36)

        let used = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.invalidCurrency("USD")) {
            try await DefaultChangeCurrenciesUseCase(settings: used, accounts: used, transactions: used).execute(.main("EUR"))
        }
    }

    @Test
    func theSecondCurrencyCanChangeOrGoAwayWhileUnused() async throws {
        let store = try InMemoryStore(settings: settings())
        let change = DefaultChangeCurrenciesUseCase(settings: store, accounts: store, transactions: store)
        try await change.execute(.second("EUR"))
        #expect(await store.load()?.currencies.second == "EUR")
        // A new second currency starts at rate 1; the old rate belonged to the old one.
        #expect(await store.load()?.currencies.rate == 1)
        try await change.execute(.second(nil))
        #expect(await store.load()?.currencies.second == nil)
        await #expect(throws: DomainError.invalidCurrency("ZZZ")) { try await change.execute(.second("ZZZ")) }
    }

    @Test
    func aSecondCurrencyWithBalancesStaysPut() async throws {
        let store = InMemoryStore(sample: .standard)
        await #expect(throws: DomainError.invalidCurrency("NIO")) {
            try await DefaultChangeCurrenciesUseCase(settings: store, accounts: store, transactions: store).execute(.second(nil))
        }
    }
}
