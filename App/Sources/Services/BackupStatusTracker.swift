import CoreData
import Foundation
import SettingsDomain

/// Remembers when CloudKit last finished uploading this iPhone's changes. SwiftData mirrors through
/// `NSPersistentCloudKitContainer`, which reports each export as an event; the time of the last
/// successful one is the honest "last backup" the settings screen shows.
final class BackupStatusTracker: BackupStatusProviding, @unchecked Sendable {
    // `UserDefaults` is thread-safe; the observer token is only set once, in `init`.
    private let defaults: UserDefaults
    private var observer: (any NSObjectProtocol)?
    private static let key = "backup.lastExportDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil,
        ) { [defaults] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
                event.type == .export, event.succeeded, let end = event.endDate
            else { return }
            defaults.set(end, forKey: Self.key)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var lastBackupDate: Date? {
        defaults.object(forKey: Self.key) as? Date
    }
}
