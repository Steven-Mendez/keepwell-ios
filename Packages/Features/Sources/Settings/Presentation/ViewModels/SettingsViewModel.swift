import Core
import Domain
import Foundation
import Observation
import SettingsDomain

@MainActor
@Observable
public final class SettingsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(SettingsOverview)
        case failed
    }

    /// A CSV or backup written to a temporary file, ready to share.
    public struct ExportedFile: Identifiable, Equatable {
        public let url: URL
        public var id: URL { url }
    }

    public private(set) var state = State.loading
    public var rateText = ""
    /// The lock screen's name as typed; saved when the field loses focus.
    public var nameText = ""
    public private(set) var errorMessage: String?
    /// A finished action worth saying, such as a restored backup.
    public private(set) var noticeMessage: String?
    public var exportedFile: ExportedFile?
    public private(set) var isWorking = false

    static let relockOptions: [TimeInterval] = [0, 60, 300, 900]
    static let reminderOptions = [1, 2, 3, 5, 7]

    private let getOverview: any GetSettingsOverviewUseCase
    private let updateSettings: any UpdateSettingsUseCase
    private let changeCurrencies: any ChangeCurrenciesUseCase
    private let exportTransactions: any ExportTransactionsUseCase
    private let eraseAllData: any EraseAllDataUseCase
    private let removePasscode: any RemovePasscodeUseCase
    private let setPreferredName: any SetPreferredNameUseCase
    private let exportBackupFile: (any ExportBackupUseCase)?
    private let restoreBackupFile: (any RestoreBackupUseCase)?
    private let now: () -> Date
    /// Signed in, erasing this iPhone first signs out, so the account's copy can't come back down.
    /// `false` means the sign-out failed and nothing may be erased.
    private let signOutBeforeErasing: (@MainActor () async -> Bool)?
    let formatter = CurrencyFormatter()

    public init(
        getOverview: any GetSettingsOverviewUseCase,
        updateSettings: any UpdateSettingsUseCase,
        changeCurrencies: any ChangeCurrenciesUseCase,
        exportTransactions: any ExportTransactionsUseCase,
        eraseAllData: any EraseAllDataUseCase,
        removePasscode: any RemovePasscodeUseCase,
        setPreferredName: any SetPreferredNameUseCase,
        exportBackup: (any ExportBackupUseCase)? = nil,
        restoreBackup: (any RestoreBackupUseCase)? = nil,
        now: @escaping () -> Date = { .now },
        signOutBeforeErasing: (@MainActor () async -> Bool)? = nil,
    ) {
        self.signOutBeforeErasing = signOutBeforeErasing
        self.removePasscode = removePasscode
        self.setPreferredName = setPreferredName
        exportBackupFile = exportBackup
        restoreBackupFile = restoreBackup
        self.getOverview = getOverview
        self.updateSettings = updateSettings
        self.changeCurrencies = changeCurrencies
        self.exportTransactions = exportTransactions
        self.eraseAllData = eraseAllData
        self.now = now
    }

    public var overview: SettingsOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public var settings: Settings? {
        overview?.settings
    }

    public func load() async {
        do {
            let overview = try await getOverview.execute()
            state = .loaded(overview)
            nameText = overview.preferredName ?? ""
            rateText = rateDisplay(overview.settings.currencies.rate)
        } catch {
            state = .failed
        }
    }

    // MARK: - Changes

    /// Saves the typed rate; an invalid one is put back to the stored value.
    public func commitRate() async {
        guard let current = settings?.currencies.rate else { return }
        // Untouched text is the rounded display of the stored rate, not a new value to save.
        guard rateText != rateDisplay(current) else { return }
        guard let rate = AmountInput.decimal(from: rateText), rate > 0 else {
            errorMessage = String(localized: "The rate has to be a number greater than zero.", bundle: #bundle)
            rateText = rateDisplay(current)
            return
        }
        guard rate != current else { return }
        await update { settings throws(DomainError) in try settings.setRate(rate) }
    }

    /// Picks the main or the second currency. The screen only offers it while nothing is kept in
    /// the one being replaced, and the use case checks it again.
    public func changeCurrency(_ change: CurrencyChange) async {
        do {
            try await changeCurrencies.execute(change)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = String(localized: "That currency is in use, so it can't change.", bundle: #bundle)
        }
    }

    /// Makes the second currency the main one, turning the rate around.
    public func swapCurrencies() async {
        await update { settings throws(DomainError) in try settings.swapCurrencies() }
    }

    /// Four decimals for "1 USD = 36.6243 NIO", six for a rate below one ("1 NIO = 0.027304 USD"),
    /// where four would round away what the rate means.
    func rateDisplay(_ rate: Decimal) -> String {
        formatter.number(rate, fractionDigits: rate < 1 ? 6 : 4).replacingOccurrences(of: ",", with: "")
    }

    public func setUnlockMethod(_ method: UnlockMethod) async {
        await update { $0.unlockMethod = method }
    }

    public func turnOffPasscode() async {
        await removePasscode.execute()
        await load()
    }

    public func commitName() async {
        guard nameText.trimmingCharacters(in: .whitespacesAndNewlines) != (overview?.preferredName ?? "") else { return }
        await setPreferredName.execute(nameText)
        await load()
    }

    public func setRelockAfter(_ seconds: TimeInterval) async {
        await update { $0.relockAfter = seconds }
    }

    public func setHidesAmounts(_ hides: Bool) async {
        await update { $0.hidesAmountsInAppSwitcher = hides }
    }

    public func setReminderDays(_ days: Int) async {
        await update { $0.paymentReminderDaysBefore = days }
    }

    public func setTimeZone(_ identifier: String) async {
        guard HomeTimeZone.isWellFormed(identifier) else { return }
        await update { $0.timeZone = identifier }
    }

    private func update(_ change: @escaping @Sendable (inout Settings) throws(DomainError) -> Void) async {
        do {
            _ = try await updateSettings.execute(change)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = Self.saveError
        }
    }

    private static var saveError: String {
        String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
    }

    // MARK: - Data

    public func export() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let csv = try await exportTransactions.execute()
            let day = now().formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepwell-\(day).csv")
            try Data(csv.utf8).write(to: url, options: .atomic)
            exportedFile = ExportedFile(url: url)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't create the file. Try again.", bundle: #bundle)
        }
    }

    public var offersBackup: Bool {
        exportBackupFile != nil && restoreBackupFile != nil
    }

    /// The full JSON backup, written to a temporary file ready to share.
    public func exportBackup() async {
        guard let exportBackupFile else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await exportBackupFile.execute(at: now())
            let day = now().formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepwell-\(day).json")
            try data.write(to: url, options: .atomic)
            exportedFile = ExportedFile(url: url)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't create the file. Try again.", bundle: #bundle)
        }
    }

    /// Restores a chosen backup file; nothing is written unless it is whole and the ledger empty.
    public func restoreBackup(_ data: Data) async {
        guard let restoreBackupFile else { return }
        isWorking = true
        defer { isWorking = false }
        noticeMessage = nil
        do {
            try await restoreBackupFile.execute(data, at: now())
            errorMessage = nil
            noticeMessage = String(localized: "Backup restored", bundle: #bundle)
            await load()
        } catch {
            errorMessage = Self.restoreMessage(error)
        }
    }

    private static func restoreMessage(_ error: BackupRestoreError) -> String {
        switch error {
        case .notEmpty:
            String(localized: "A backup can only be restored when there's no data yet. Delete all your data first.", bundle: #bundle)
        case .newerVersion:
            String(localized: "This backup is from a newer version of Keepwell. Update the app and try again.", bundle: #bundle)
        case .notBackup, .invalid:
            String(localized: "This file isn't a Keepwell backup, or it's damaged. Nothing was restored.", bundle: #bundle)
        case .failed:
            String(localized: "We couldn't restore the backup. Try again.", bundle: #bundle)
        }
    }

    /// Returns whether everything was deleted, so the app can go back to the start.
    public func eraseAll() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        if let signOutBeforeErasing, await !signOutBeforeErasing() {
            errorMessage = String(localized: "We couldn't delete your data. Try again.", bundle: #bundle)
            return false
        }
        do {
            try await eraseAllData.execute()
            return true
        } catch {
            errorMessage = String(localized: "We couldn't delete your data. Try again.", bundle: #bundle)
            return false
        }
    }
}
