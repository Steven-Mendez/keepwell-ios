/// Which engine keeps this device's data in sync. Only one may run: if CloudKit kept mirroring
/// while the custom engine also uploaded, both would bring the same records back and duplicate them.
public enum SyncMode: String, Codable, CaseIterable, Sendable {
    /// SwiftData mirrored to the person's CloudKit private database, when "iCloud backup" is on.
    case localWithICloud
    /// Keepwell's own sync (Premium, shared with the web app). CloudKit mirroring is off and the
    /// same on-device store stays the source of truth.
    case customCloudSync
}
