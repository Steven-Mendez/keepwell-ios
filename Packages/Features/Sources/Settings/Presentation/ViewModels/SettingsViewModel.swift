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

    /// A CSV written to a temporary file, ready to share.
    public struct ExportedFile: Identifiable, Equatable {
        public let url: URL
        public var id: URL { url }
    }

    public private(set) var state = State.loading
    public var rateText = ""
    public private(set) var errorMessage: String?
    /// Set once the iCloud switch changed, since the store only switches on the next launch.
    public private(set) var backupChangeIsPending = false
    public var exportedFile: ExportedFile?
    /// The outcome of the last CSV import, shown under the data card.
    public private(set) var importMessage: String?
    /// The language picked in this session; it shows once Keepwell is opened again.
    public private(set) var chosenLanguage: AppLanguage
    public private(set) var languageNeedsReopen = false
    /// The outcome of the last backup or restore, shown under the iCloud status.
    public private(set) var backupMessage: String?
    public private(set) var isWorking = false

    static let relockOptions: [TimeInterval] = [0, 60, 300, 900]
    static let reminderOptions = [1, 2, 3, 5, 7]
    static let capThresholdOptions: [Decimal] = [0.5, 0.7, 0.8, 0.9, 1]

    private let getOverview: any GetSettingsOverviewUseCase
    private let updateSettings: any UpdateSettingsUseCase
    private let setICloudBackup: any SetICloudBackupUseCase
    private let exportTransactions: any ExportTransactionsUseCase
    private let importTransactions: any ImportTransactionsUseCase
    private let createBackup: any CreateBackupUseCase
    private let restoreBackup: any RestoreBackupUseCase
    private let languagePreference: any LanguagePreference
    private let eraseAllData: any EraseAllDataUseCase
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    public init(
        getOverview: any GetSettingsOverviewUseCase,
        updateSettings: any UpdateSettingsUseCase,
        setICloudBackup: any SetICloudBackupUseCase,
        exportTransactions: any ExportTransactionsUseCase,
        importTransactions: any ImportTransactionsUseCase,
        createBackup: any CreateBackupUseCase,
        restoreBackup: any RestoreBackupUseCase,
        language: any LanguagePreference,
        eraseAllData: any EraseAllDataUseCase,
        now: @escaping () -> Date = { .now },
    ) {
        self.getOverview = getOverview
        self.updateSettings = updateSettings
        self.setICloudBackup = setICloudBackup
        self.exportTransactions = exportTransactions
        self.importTransactions = importTransactions
        self.createBackup = createBackup
        self.restoreBackup = restoreBackup
        languagePreference = language
        chosenLanguage = language.current
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
            rateText = formatter.number(overview.settings.currencies.rate, fractionDigits: 4).replacingOccurrences(of: ",", with: "")
        } catch {
            state = .failed
        }
    }

    // MARK: - Changes

    /// Saves the typed rate; an invalid one is put back to the stored value.
    public func commitRate() async {
        guard let current = settings?.currencies.rate else { return }
        guard let rate = AmountInput.decimal(from: rateText), rate > 0 else {
            errorMessage = String(localized: "The rate has to be a number greater than zero.", bundle: #bundle)
            rateText = formatter.number(current, fractionDigits: 4).replacingOccurrences(of: ",", with: "")
            return
        }
        guard rate != current else { return }
        await update { settings throws(DomainError) in try settings.setRate(rate) }
    }

    public func setUnlockMethod(_ method: UnlockMethod) async {
        await update { $0.unlockMethod = method }
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

    public func setCapThreshold(_ threshold: Decimal) async {
        await update { $0.additionalCapAlertThreshold = threshold }
    }

    public func setICloudBackup(_ isEnabled: Bool) async {
        do {
            try await setICloudBackup.execute(isEnabled)
            backupChangeIsPending.toggle()
            errorMessage = nil
            await load()
        } catch {
            errorMessage = Self.saveError
        }
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

    /// Reads a CSV the person picked. Files from the picker sit outside the sandbox, so access is
    /// requested for the read and released right after.
    public func importFile(at url: URL) async {
        isWorking = true
        defer { isWorking = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            importMessage = nil
            errorMessage = String(localized: "We couldn't read that file. Export it again as CSV (UTF-8).", bundle: #bundle)
            return
        }
        do {
            let summary = try await importTransactions.execute(csv: text)
            errorMessage = nil
            importMessage = Self.importMessage(summary)
            await load()
        } catch {
            importMessage = nil
            errorMessage = String(localized: "We couldn't import the file. Try again.", bundle: #bundle)
        }
    }

    public static func importMessage(_ summary: ImportSummary) -> String {
        let imported = summary.imported
        let skipped = summary.skipped
        let done = String(localized: "\(imported) transactions imported", bundle: #bundle)
        guard skipped > 0 else { return done }
        return done + " · " + String(localized: "\(skipped) rows skipped", bundle: #bundle)
    }

    public func chooseLanguage(_ language: AppLanguage) {
        chosenLanguage = language
        languageNeedsReopen = languagePreference.choose(language)
    }

    /// Writes a full backup file and offers it to share or save (iCloud Drive, Files).
    public func backUpNow() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let data = try await createBackup.execute()
            let day = now().formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Keepwell-\(day).keepwell.json")
            try data.write(to: url, options: .atomic)
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            backupMessage = String(localized: "Backup ready · \(size). Save it in iCloud Drive or Files.", bundle: #bundle)
            errorMessage = nil
            exportedFile = ExportedFile(url: url)
        } catch {
            backupMessage = nil
            errorMessage = String(localized: "We couldn't create the backup. Try again.", bundle: #bundle)
        }
    }

    /// Replaces all data with a backup file the person picked. Returns whether it did, so the app
    /// can refresh every screen.
    public func restore(from url: URL) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = String(localized: "We couldn't read that file.", bundle: #bundle)
            return false
        }
        do {
            let summary = try await restoreBackup.execute(data)
            let when = summary.backupDate.formatted(date: .abbreviated, time: .shortened)
            let movements = summary.transactions
            backupMessage = String(localized: "Restored the backup from \(when) · \(movements) transactions", bundle: #bundle)
            errorMessage = nil
            await load()
            return true
        } catch {
            backupMessage = nil
            if case .corruptedData = error {
                errorMessage = String(localized: "That file isn't a Keepwell backup, so nothing was changed.", bundle: #bundle)
            } else {
                errorMessage = String(localized: "We couldn't restore the backup. Try again.", bundle: #bundle)
            }
            return false
        }
    }

    /// Returns whether everything was deleted, so the app can go back to the start.
    public func eraseAll() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await eraseAllData.execute()
            return true
        } catch {
            errorMessage = String(localized: "We couldn't delete your data. Try again.", bundle: #bundle)
            return false
        }
    }
}
