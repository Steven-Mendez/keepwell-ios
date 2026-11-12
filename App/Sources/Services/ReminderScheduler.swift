import Foundation
import HomePresentation
import UserNotifications

/// Keeps the system's pending notifications in step with home's reminders, and takes delivered or
/// pending ones off when they were read or deleted. A notification's request identifier is its
/// shared id, which is also what the server sends as `apns-collapse-id`, so a push and a local
/// notification for the same occurrence are the same thing to every call here.
@MainActor
final class ReminderScheduler {
    static let plannedCategory = "keepwell.planned"
    static let confirmAction = "keepwell.confirm"
    static let postponeAction = "keepwell.postpone"
    static let transactionKey = "transactionID"
    static let notificationKey = "notification_id"
    static let targetKey = "target"
    /// iOS keeps at most 64 pending notifications per app and silently drops the rest, so only
    /// the soonest are scheduled; the next reschedule adds the later ones.
    static let pendingLimit = 64
    /// When each id was handed to the system. Once that moment has passed the id is told, and it is
    /// never scheduled again: a notification is sent once per occurrence, as the server does.
    static let scheduledKey = "keepwell.reminders.scheduled"
    /// Postponed reminders, by the morning they come back, so rescheduling doesn't drop them.
    static let postponedKey = "keepwell.reminders.postponed"
    /// Ids carry their day, so old ones never match again; this only keeps the list short.
    static let retention: TimeInterval = 120 * 86400
    /// How long a one-shot (a budget crossed, a price that went up) waits: right away, but late
    /// enough that the date is still ahead when the system receives it.
    static let oneShotDelay: TimeInterval = 5

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.plannedCategory,
                actions: [
                    UNNotificationAction(
                        identifier: Self.confirmAction,
                        title: String(localized: "Confirm"),
                        options: [.authenticationRequired],
                    ),
                    UNNotificationAction(identifier: Self.postponeAction, title: String(localized: "Postpone")),
                ],
                intentIdentifiers: [],
            ),
        ])
    }

    private func load(_ key: String) -> [String: Double] {
        defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    func schedule(_ reminders: [Reminder], now: Date = .now) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let moment = now.timeIntervalSince1970
        var scheduled = load(Self.scheduledKey).filter { $0.value > moment - Self.retention }
        let postponed = load(Self.postponedKey).filter { $0.value > moment }
        defaults.set(postponed, forKey: Self.postponedKey)

        // Told already: its moment has passed.
        let told = Set(scheduled.filter { $0.value <= moment }.keys)
        let due = reminders.filter { !told.contains($0.id) }
        // A one-shot still waiting its few seconds stays: replacing it would delay it again and again.
        let waiting = Set(due.filter { $0.isOneShot && scheduled[$0.id] != nil }.map(\.id))
        let keep = waiting.union(postponed.keys)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let additions = due.filter { !waiting.contains($0.id) }.map { reminder in
            reminder.isOneShot ? reminder.at(now.addingTimeInterval(Self.oneShotDelay)) : reminder
        }
        for reminder in additions.sorted(by: { $0.date < $1.date }).prefix(Self.pendingLimit) {
            try? await center.add(request(for: reminder))
            scheduled[reminder.id] = reminder.date.timeIntervalSince1970
        }
        defaults.set(scheduled, forKey: Self.scheduledKey)
    }

    /// "Postpone": the same reminder tomorrow morning.
    func postpone(_ content: UNNotificationContent, identifier: String) async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(of: morning), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        var postponed = load(Self.postponedKey)
        postponed[identifier] = morning.timeIntervalSince1970
        defaults.set(postponed, forKey: Self.postponedKey)
    }

    /// Notifications read or deleted somewhere (this iPhone, another one, the web): off the
    /// Notification Center and out of the schedule.
    func remove(ids: [String]) async {
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let delivered = await center.deliveredNotifications().filter { notification in
            let request = notification.request
            let carried = request.content.userInfo[Self.notificationKey] as? String
            return wanted.contains(request.identifier) || carried.map(wanted.contains) == true
        }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier))
    }

    /// The app icon's number: what is unread in the inbox.
    func setBadge(_ count: Int) async {
        try? await center.setBadgeCount(count)
    }

    /// The server sends from now on: nothing local may arrive twice.
    func removeAllPending() async {
        center.removeAllPendingNotificationRequests()
        defaults.removeObject(forKey: Self.postponedKey)
    }

    /// After "Delete all my data".
    func removeAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        defaults.removeObject(forKey: Self.scheduledKey)
        defaults.removeObject(forKey: Self.postponedKey)
        await setBadge(0)
    }

    private func request(for reminder: Reminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.kind.rawValue
        var info: [String: Any] = [Self.notificationKey: reminder.id, Self.targetKey: reminder.target]
        if let transactionID = reminder.transactionID {
            content.categoryIdentifier = Self.plannedCategory
            info[Self.transactionKey] = transactionID.uuidString
        }
        content.userInfo = info
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(of: reminder.date), repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    private static func components(of date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
}
