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
    /// iOS keeps at most 64 pending notifications per app and silently drops the rest, so only
    /// the soonest are scheduled; the next reschedule (every time home loads) adds the later ones.
    static let pendingLimit = 64
    /// Budget and price-increase alerts already handed to the system. They report something that
    /// already happened, so unlike the dated reminders they must not be sent again each time home
    /// reschedules. The key keeps its old name so alerts announced before stay announced.
    static let announcedKey = "keepwell.reminders.announcedBudgets"
    /// Ids carry their month or their charge, so old ones never match again; this only keeps the
    /// list short.
    static let announcedLimit = 200

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

    func schedule(_ reminders: [Reminder]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        var announced = defaults.stringArray(forKey: Self.announcedKey) ?? []
        // A one-shot alert still waiting its few seconds stays: removing it would lose it for good.
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) && !announced.contains(String($0.dropFirst(Self.prefix.count))) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let due = reminders.filter { !(Self.isOneShot($0) && announced.contains($0.id)) }
        for reminder in due.sorted(by: { $0.date < $1.date }).prefix(Self.pendingLimit) {
            try? await center.add(request(for: reminder))
            if Self.isOneShot(reminder) {
                announced.append(reminder.id)
            }
        }
        defaults.set(Array(announced.suffix(Self.announcedLimit)), forKey: Self.announcedKey)
    }

    private static func isOneShot(_ reminder: Reminder) -> Bool {
        switch reminder.kind {
        case .budget, .priceIncrease: true
        default: false
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
        defaults.removeObject(forKey: Self.announcedKey)
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
