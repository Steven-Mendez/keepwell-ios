import Foundation

/// Device-local storage choices. The iCloud switch has to be known before the `ModelContainer`
/// exists, so it lives in `UserDefaults` rather than in the synced settings.
public struct StorePreferences: @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe; it just isn't marked `Sendable`.
    private let defaults: UserDefaults
    private static let iCloudKey = "persistence.iCloudBackupEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On by default, as the design's onboarding and settings show.
    public var isICloudBackupEnabled: Bool {
        get { defaults.object(forKey: Self.iCloudKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.iCloudKey) }
    }

    /// The store to open: the CloudKit-mirrored one when backup is on, on-device only otherwise.
    /// Both use the same file, so turning backup back on uploads what was recorded meanwhile.
    public func store(cloudKitContainer: String) -> PersistenceStore {
        isICloudBackupEnabled && !cloudKitContainer.isEmpty ? .cloudKit(containerIdentifier: cloudKitContainer) : .local
    }

    public func reset() {
        defaults.removeObject(forKey: Self.iCloudKey)
    }
}
