import Domain
import DomainSamples
import SettingsDomain
import Testing
@testable import SettingsPresentation

/// "Delete all my data" while signed in signs out first, and erases only if that worked.
@Suite("Erase all data")
@MainActor
struct EraseAllDataTests {
    private func model(store: InMemoryStore, signOut: (@MainActor () async -> Bool)?) -> SettingsViewModel {
        let passcodes = InMemoryPasscodeStore(name: "Steven")
        return SettingsViewModel(
            getOverview: DefaultGetSettingsOverviewUseCase(
                settings: store, categories: store, cards: store, accounts: store, transactions: store, rules: store,
                passcodes: passcodes, profile: passcodes,
            ),
            updateSettings: DefaultUpdateSettingsUseCase(settings: store),
            changeCurrencies: DefaultChangeCurrenciesUseCase(settings: store, accounts: store, transactions: store),
            exportTransactions: DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store),
            eraseAllData: DefaultEraseAllDataUseCase(eraser: store),
            removePasscode: DefaultRemovePasscodeUseCase(passcodes: passcodes),
            setPreferredName: DefaultSetPreferredNameUseCase(profile: passcodes),
            signOutBeforeErasing: signOut,
        )
    }

    @Test
    func signsOutThenErases() async {
        let store = InMemoryStore(sample: .standard)
        var signedOutWhileDataRemained = false
        let viewModel = model(store: store) {
            signedOutWhileDataRemained = await !store.fetchAccounts().isEmpty
            return true
        }
        #expect(await viewModel.eraseAll())
        #expect(signedOutWhileDataRemained)
        #expect(await store.fetchAccounts().isEmpty)
    }

    @Test
    func aFailedSignOutErasesNothingAndSaysSo() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = model(store: store) { false }
        #expect(await viewModel.eraseAll() == false)
        #expect(viewModel.errorMessage == "We couldn't delete your data. Try again.")
        #expect(await store.fetchAccounts().count == SampleData.standard.accounts.count)
    }

    @Test
    func signedOutErasesAsBefore() async {
        let store = InMemoryStore(sample: .standard)
        #expect(await model(store: store, signOut: nil).eraseAll())
        #expect(await store.fetchAccounts().isEmpty)
    }
}
