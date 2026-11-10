import Domain
import DomainSamples
import FeatureTestSupport
import SettingsDomain
import SwiftUI
import Testing
@testable import SettingsPresentation

@Suite("Settings snapshots")
@MainActor
struct SettingsSnapshotTests {
    private func loaded() async -> SettingsViewModel {
        let store = InMemoryStore(sample: .standard)
        let passcodes = InMemoryPasscodeStore(name: "Steven")
        let viewModel = SettingsViewModel(
            getOverview: DefaultGetSettingsOverviewUseCase(
                settings: store, categories: store, cards: store, passcodes: passcodes, profile: passcodes,
            ),
            updateSettings: DefaultUpdateSettingsUseCase(settings: store),
            exportTransactions: DefaultExportTransactionsUseCase(transactions: store, accounts: store, cards: store, categories: store),
            importTransactions: DefaultImportTransactionsUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store, rules: store,
            ),
            eraseAllData: DefaultEraseAllDataUseCase(eraser: store),
            removePasscode: DefaultRemovePasscodeUseCase(passcodes: passcodes),
            setPreferredName: DefaultSetPreferredNameUseCase(profile: passcodes),
            now: { SampleData.defaultReferenceDate },
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func settings() async {
        await assertScreenSnapshot(of: SettingsView(viewModel: loaded(), onBack: {}, onErased: {}), height: 1400)
    }

    @Test
    func settingsLight() async {
        await assertScreenSnapshot(
            of: SettingsView(viewModel: loaded(), onBack: {}, onErased: {}),
            height: 1400,
            named: "light",
            colorScheme: .light,
        )
    }
}
