import Domain
import Foundation
import SwiftData

/// A single row. Stored with the rest of the data so a restore on a new iPhone brings the
/// currencies and rate back too.
@Model
public final class SettingsRecord {
    var principal = "USD"
    var second: String?
    var rate = "1"
    var unlockMethodRaw = UnlockMethod.biometrics.rawValue
    var relockAfter = 60.0
    var hidesAmountsInAppSwitcher = true
    var isICloudBackupEnabled = true
    var paymentReminderDaysBefore = 3
    /// From when cards could have additionals; kept because CloudKit can't remove attributes.
    var additionalCapAlertThreshold = "0.8"
    var hasCompletedOnboarding = false
    var updatedAt = Date.now

    init() {}

    func update(from settings: Settings) {
        principal = settings.currencies.principal
        second = settings.currencies.second
        rate = DecimalCoding.string(settings.currencies.rate)
        unlockMethodRaw = settings.unlockMethod.rawValue
        relockAfter = settings.relockAfter
        hidesAmountsInAppSwitcher = settings.hidesAmountsInAppSwitcher
        isICloudBackupEnabled = settings.isICloudBackupEnabled
        paymentReminderDaysBefore = settings.paymentReminderDaysBefore
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        updatedAt = .now
    }

    func toDomain() throws(DomainCorruption) -> Settings {
        let currencies: CurrencySettings
        do {
            currencies = try CurrencySettings(principal: principal, second: second, rate: DecimalCoding.decimal(rate))
        } catch let error as DomainCorruption {
            throw error
        } catch {
            throw DomainCorruption("Currency settings rate \(rate)")
        }
        return try Settings(
            currencies: currencies,
            unlockMethod: UnlockMethod(rawValue: unlockMethodRaw) ?? .biometrics,
            relockAfter: relockAfter,
            hidesAmountsInAppSwitcher: hidesAmountsInAppSwitcher,
            isICloudBackupEnabled: isICloudBackupEnabled,
            paymentReminderDaysBefore: paymentReminderDaysBefore,
            hasCompletedOnboarding: hasCompletedOnboarding,
        )
    }
}
