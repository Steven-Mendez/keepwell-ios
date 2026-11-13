import Domain
import DomainSamples
import Foundation
import SettingsDomain
import Testing
@testable import SettingsPresentation

/// "Export backup" and "Restore backup" in Settings: what the person is told.
@Suite("Backup in settings")
@MainActor
struct BackupViewModelTests {
    private struct Restore: RestoreBackupUseCase {
        let error: BackupRestoreError?

        func execute(_: Data, at _: Date) async throws(BackupRestoreError) {
            if let error {
                throw error
            }
        }
    }

    private struct Export: ExportBackupUseCase {
        func execute(at _: Date) async throws(DomainError) -> Data {
            Data("{}".utf8)
        }
    }

    private func model(restoring error: BackupRestoreError?) -> SettingsViewModel {
        let store = InMemoryStore(sample: .standard)
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
            exportBackup: Export(),
            restoreBackup: Restore(error: error),
        )
    }

    @Test
    func exportsAJSONFile() async {
        let viewModel = model(restoring: nil)
        #expect(viewModel.offersBackup)
        await viewModel.exportBackup()
        #expect(viewModel.exportedFile?.url.pathExtension == "json")
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func saysWhenTheBackupIsRestored() async {
        let viewModel = model(restoring: nil)
        await viewModel.restoreBackup(Data())
        #expect(viewModel.restoreOutcome == .init(title: "Backup restored", reason: nil))
        #expect(viewModel.errorMessage == nil)
    }

    @Test(arguments: [
        (BackupRestoreError.notEmpty, "A backup can only be restored when there's no data yet. Delete all your data first."),
        (.newerVersion(2), "This backup is from a newer version of Keepwell. Update the app and try again."),
        (.notBackup, "This file isn't a Keepwell backup, or it's damaged. Nothing was restored."),
        (.invalid("transaction[3]: amount"), "This file isn't a Keepwell backup, or it's damaged. Nothing was restored."),
        (.failed, "We couldn't restore the backup. Try again."),
    ])
    func explainsWhyARestoreFailed(error: BackupRestoreError, message: String) async {
        let viewModel = model(restoring: error)
        await viewModel.restoreBackup(Data())
        // An alert, not a line at the end of Settings that the person would have to scroll to.
        #expect(viewModel.restoreOutcome == .init(title: "Backup not restored", reason: message))
        #expect(viewModel.restoreOutcome?.isFailure == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func aFileThatCantBeReadIsSaidLikeAnyOtherRefusal() {
        let viewModel = model(restoring: nil)
        viewModel.restoreBackupFileUnreadable()
        #expect(viewModel.restoreOutcome == .init(
            title: "Backup not restored",
            reason: "We couldn't open that file. Nothing was restored.",
        ))
    }
}
