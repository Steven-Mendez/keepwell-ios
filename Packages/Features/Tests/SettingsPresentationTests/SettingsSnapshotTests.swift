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

    private func screen(_ viewModel: SettingsViewModel) -> SettingsView {
        SettingsView(
            viewModel: viewModel,
            onBack: {},
            onErased: {},
            about: SettingsAbout(version: "1.0.1 (1)", privacyPolicy: URL(string: "https://example.com/privacy")),
        )
    }

    @Test
    func settings() async {
        await assertScreenSnapshot(of: screen(loaded()), height: 2150)
    }

    @Test
    func settingsLight() async {
        await assertScreenSnapshot(of: screen(loaded()), height: 2150, named: "light", colorScheme: .light)
    }

    /// iPhone SE width: long Spanish-length labels and the rate field still fit on one row.
    @Test
    func settingsOnASmallIPhone() async {
        await assertScreenSnapshot(of: screen(loaded()), width: 320, height: 1300)
    }

    /// The largest text sizes stack values under their titles instead of truncating them.
    @Test
    func settingsWithLargeText() async {
        await assertScreenSnapshot(
            of: screen(loaded()).environment(\.dynamicTypeSize, .accessibility2),
            height: 1600,
            named: "accessibility2",
            colorScheme: .light,
        )
    }
}
