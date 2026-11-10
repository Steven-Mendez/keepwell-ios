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
        let overview = try await DefaultGetSettingsOverviewUseCase(settings: store, categories: store, cards: store)
            .execute()
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
            settings: store, categories: store, cards: store, passcodes: lock, profile: lock,
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
