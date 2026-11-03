import Foundation
import HomePresentation
import UserNotifications

/// Keeps the system's pending notifications in step with home's reminders. Everything it adds is
/// prefixed, so rescheduling never touches notifications it doesn't own.
@MainActor
final class ReminderScheduler {
    static let plannedCategory = "keepwell.planned"
    static let confirmAction = "keepwell.confirm"
    static let postponeAction = "keepwell.postpone"
    static let transactionKey = "transactionID"
    private static let prefix = "keepwell."

    private let center = UNUserNotificationCenter.current()

    init() {
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

    func schedule(_ reminders: [Reminder]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for reminder in reminders {
            try? await center.add(request(for: reminder))
        }
    }

    /// "Postpone": the same reminder tomorrow morning.
    func postpone(_ content: UNNotificationContent, identifier: String) async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(of: morning), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// After "Delete all my data".
    func removeAll() async {
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    private func request(for reminder: Reminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        if case let .planned(id) = reminder.kind {
            content.categoryIdentifier = Self.plannedCategory
            content.userInfo = [Self.transactionKey: id.uuidString]
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(of: reminder.date), repeats: false)
        return UNNotificationRequest(identifier: Self.prefix + reminder.id, content: content, trigger: trigger)
    }

    private static func components(of date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
}
