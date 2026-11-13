import Foundation
import SwiftData

/// V11's shape of the records V12 changed, kept so a store written by V1 to V11 still opens and
/// migrates. Separate from `KeepwellSchema.swift` only to keep that file readable.
extension KeepwellSchemaV11 {
    /// The settings row before it carried the home time zone. V1 to V10 share it.
    @Model
    public final class SettingsRecord {
        var principal = "USD"
        var second: String?
        var rate = "1"
        var unlockMethodRaw = "biometrics"
        var relockAfter = 60.0
        var hidesAmountsInAppSwitcher = true
        var isICloudBackupEnabled = true
        var paymentReminderDaysBefore = 3
        var additionalCapAlertThreshold = "0.8"
        var hasCompletedOnboarding = false
        var updatedAt = Date.now

        init() {}
    }
}
