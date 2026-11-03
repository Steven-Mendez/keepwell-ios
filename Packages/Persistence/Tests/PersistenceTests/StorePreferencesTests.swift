import Domain
import Foundation
import Testing
@testable import Persistence

@Suite("Store preferences")
struct StorePreferencesTests {
    private func makePreferences() throws -> StorePreferences {
        let defaults = try #require(UserDefaults(suiteName: "StorePreferencesTests.\(UUID().uuidString)"))
        return StorePreferences(defaults: defaults)
    }

    @Test
    func iCloudBackupIsOnByDefault() throws {
        let preferences = try makePreferences()
        #expect(preferences.isICloudBackupEnabled)
        #expect(preferences.store(cloudKitContainer: "iCloud.test") == .cloudKit(containerIdentifier: "iCloud.test"))
    }

    @Test
    func turningBackupOffUsesTheLocalStore() throws {
        let preferences = try makePreferences()
        preferences.isICloudBackupEnabled = false
        #expect(preferences.store(cloudKitContainer: "iCloud.test") == .local)
        preferences.reset()
        #expect(preferences.isICloudBackupEnabled)
    }

    @Test
    func missingContainerFallsBackToLocal() throws {
        #expect(try makePreferences().store(cloudKitContainer: "") == .local)
    }
}

@Suite("Store preferences as backup preference")
struct BackupPreferenceConformanceTests {
    @Test
    func setsThroughTheDomainContract() throws {
        let defaults = try #require(UserDefaults(suiteName: "BackupPreference.\(UUID().uuidString)"))
        let preference: any BackupPreference = StorePreferences(defaults: defaults)
        preference.setICloudBackupEnabled(false)
        #expect(!preference.isICloudBackupEnabled)
    }
}
