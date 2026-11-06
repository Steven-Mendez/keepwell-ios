import Domain
import Foundation

/// Device-local storage choices. The iCloud switch has to be known before the `ModelContainer`
/// exists, so it lives in `UserDefaults` rather than in the synced settings.
public struct StorePreferences: @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe; it just isn't marked `Sendable`.
    private let defaults: UserDefaults
    private static let iCloudKey = "persistence.iCloudBackupEnabled"
    private static let syncModeKey = "persistence.syncMode"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On by default, as the design's onboarding and settings show.
    public var isICloudBackupEnabled: Bool {
        get { defaults.object(forKey: Self.iCloudKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.iCloudKey) }
    }

    /// iCloud until the person moves to Keepwell's own sync. Read before the store opens, like
    /// the iCloud switch, because it decides whether CloudKit mirroring starts at all.
    public var syncMode: SyncMode {
        get { defaults.string(forKey: Self.syncModeKey).flatMap(SyncMode.init(rawValue:)) ?? .localWithICloud }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.syncModeKey) }
    }

    /// The store to open: the CloudKit-mirrored one when iCloud sync is the mode and backup is on,
    /// on-device only otherwise. Every case uses the same file, so switching never copies records:
    /// with `customCloudSync` CloudKit simply stops mirroring and the custom engine starts from it.
    public func store(cloudKitContainer: String) -> PersistenceStore {
        guard syncMode == .localWithICloud, isICloudBackupEnabled, !cloudKitContainer.isEmpty else { return .local }
        return .cloudKit(containerIdentifier: cloudKitContainer)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.iCloudKey)
    }
}

extension StorePreferences: BackupPreference {
    public func setICloudBackupEnabled(_ isEnabled: Bool) {
        isICloudBackupEnabled = isEnabled
    }
}

extension StorePreferences: ProfileRepository {
    private static let nameKey = "lock.preferredName"

    public func preferredName() async -> String? {
        defaults.string(forKey: Self.nameKey)
    }

    public func setPreferredName(_ name: String?) async {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.nameKey)
        } else {
            defaults.set(trimmed, forKey: Self.nameKey)
        }
    }
}
