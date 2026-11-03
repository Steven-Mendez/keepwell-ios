import Domain
import Foundation

/// When this iPhone's data last reached iCloud, as the sync engine reports it.
public protocol BackupStatusProviding: Sendable {
    var lastBackupDate: Date? { get }
}

/// What the settings screen shows besides the settings themselves.
public struct SettingsOverview: Hashable, Sendable {
    public let settings: Settings
    public let expenseCategoryCount: Int
    public let incomeCategoryCount: Int
    /// Cards and transfer channels.
    public let paymentMethodCount: Int
    /// The device-local switch, which can differ from the synced setting on another device.
    public let isICloudBackupEnabled: Bool
    /// `nil` until the first upload finishes (or with backup off).
    public let lastBackupDate: Date?
    /// Whether this iPhone has an app passcode; it's device-local, so not part of `settings`.
    public let hasPasscode: Bool
    /// The name the lock screen greets with.
    public let preferredName: String?

    public init(
        settings: Settings,
        expenseCategoryCount: Int,
        incomeCategoryCount: Int,
        paymentMethodCount: Int,
        isICloudBackupEnabled: Bool,
        lastBackupDate: Date? = nil,
        hasPasscode: Bool = false,
        preferredName: String? = nil,
    ) {
        self.lastBackupDate = lastBackupDate
        self.hasPasscode = hasPasscode
        self.preferredName = preferredName
        self.settings = settings
        self.expenseCategoryCount = expenseCategoryCount
        self.incomeCategoryCount = incomeCategoryCount
        self.paymentMethodCount = paymentMethodCount
        self.isICloudBackupEnabled = isICloudBackupEnabled
    }
}

public protocol GetSettingsOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> SettingsOverview
}

public struct DefaultGetSettingsOverviewUseCase: GetSettingsOverviewUseCase {
    private let settings: any SettingsRepository
    private let categories: any CategoryRepository
    private let cards: any CardRepository
    private let backup: any BackupPreference
    private let status: (any BackupStatusProviding)?
    private let passcodes: (any PasscodeRepository)?
    private let profile: (any ProfileRepository)?

    public init(
        settings: any SettingsRepository,
        categories: any CategoryRepository,
        cards: any CardRepository,
        backup: any BackupPreference,
        status: (any BackupStatusProviding)? = nil,
        passcodes: (any PasscodeRepository)? = nil,
        profile: (any ProfileRepository)? = nil,
    ) {
        self.status = status
        self.passcodes = passcodes
        self.profile = profile
        self.settings = settings
        self.categories = categories
        self.cards = cards
        self.backup = backup
    }

    public func execute() async throws(DomainError) -> SettingsOverview {
        let current = try await settings.load() ?? Settings(currencies: .initial)
        let allCategories = try await categories.fetchCategories()
        return try await SettingsOverview(
            settings: current,
            expenseCategoryCount: allCategories.count { $0.kind == .expense },
            incomeCategoryCount: allCategories.count { $0.kind == .income },
            paymentMethodCount: cards.fetchCards().count,
            isICloudBackupEnabled: backup.isICloudBackupEnabled,
            lastBackupDate: backup.isICloudBackupEnabled ? status?.lastBackupDate : nil,
            hasPasscode: passcodes?.hasPasscode() ?? false,
            preferredName: profile?.preferredName(),
        )
    }
}

/// Saves a change to the settings. Changes to the rate only affect movements recorded from now
/// on: each movement keeps the rate it was recorded with (rule 2).
public protocol UpdateSettingsUseCase: Sendable {
    func execute(_ change: @Sendable (inout Settings) throws(DomainError) -> Void) async throws(DomainError) -> Settings
}

public struct DefaultUpdateSettingsUseCase: UpdateSettingsUseCase {
    private let settings: any SettingsRepository

    public init(settings: any SettingsRepository) {
        self.settings = settings
    }

    public func execute(_ change: @Sendable (inout Settings) throws(DomainError) -> Void) async throws(DomainError) -> Settings {
        var updated = try await settings.load() ?? Settings(currencies: .initial)
        try change(&updated)
        try await settings.save(updated)
        return updated
    }
}

extension Settings {
    /// Replaces the manual rate, keeping both currencies.
    public mutating func setRate(_ rate: Decimal) throws(DomainError) {
        currencies = try CurrencySettings(principal: currencies.principal, second: currencies.second, rate: rate)
    }
}

/// The device's iCloud switch. It picks the store at launch, so it takes effect next time the
/// app opens; the synced setting is updated too so other screens read the same value.
public protocol SetICloudBackupUseCase: Sendable {
    func execute(_ isEnabled: Bool) async throws(DomainError)
}

public struct DefaultSetICloudBackupUseCase: SetICloudBackupUseCase {
    private let backup: any BackupPreference
    private let settings: any SettingsRepository

    public init(backup: any BackupPreference, settings: any SettingsRepository) {
        self.backup = backup
        self.settings = settings
    }

    public func execute(_ isEnabled: Bool) async throws(DomainError) {
        backup.setICloudBackupEnabled(isEnabled)
        guard var current = try await settings.load() else { return }
        current.isICloudBackupEnabled = isEnabled
        try await settings.save(current)
    }
}

/// Turns the app passcode off; the lock goes back to Face ID or the iPhone passcode.
public protocol RemovePasscodeUseCase: Sendable {
    func execute() async
}

public struct DefaultRemovePasscodeUseCase: RemovePasscodeUseCase {
    private let passcodes: any PasscodeRepository

    public init(passcodes: any PasscodeRepository) {
        self.passcodes = passcodes
    }

    public func execute() async {
        await passcodes.removePasscode()
    }
}

/// "Delete all my data": this device and the iCloud copy (App Store guideline 5.1.1).
public protocol EraseAllDataUseCase: Sendable {
    func execute() async throws(DomainError)
}

/// Removes the iCloud copy itself. Deleting local records only reaches iCloud while sync is on and
/// running, so with iCloud off (or before the deletions upload) the cloud copy would survive.
public protocol CloudCopyEraser: Sendable {
    func eraseCloudCopy() async throws(DomainError)
}

public struct DefaultEraseAllDataUseCase: EraseAllDataUseCase {
    private let eraser: any DataEraser
    private let cloud: (any CloudCopyEraser)?

    public init(eraser: any DataEraser, cloud: (any CloudCopyEraser)? = nil) {
        self.eraser = eraser
        self.cloud = cloud
    }

    /// This device first, so a failure to reach iCloud never leaves local data behind; running it
    /// again then only retries the cloud.
    public func execute() async throws(DomainError) {
        try await eraser.eraseAll()
        try await cloud?.eraseCloudCopy()
    }
}
