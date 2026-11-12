import HomeDomain
import UIKit
import UserNotifications

/// The app delegate for what iOS tells the app about notifications: taps (and the "Confirm" and
/// "Postpone" actions), the push token, and the server's silent pushes. iOS can deliver any of
/// them before the store has opened, so each waits until the root view installs its handler.
@MainActor
final class NotificationResponder: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    enum Action {
        case confirm(UUID, notificationID: String?)
        case postpone(UNNotificationContent, identifier: String)
        /// A tap on the notification itself, local or pushed: read it and show what it is about.
        case open(notificationID: String?, target: LedgerNotification.Target?)
    }

    var handler: ((Action) async -> Void)? {
        didSet { flush() }
    }

    /// The APNs device token, every time iOS hands it over (each launch that registers).
    var tokenHandler: ((Data) async -> Void)? {
        didSet {
            if let token = lastToken, let tokenHandler {
                Task { await tokenHandler(token) }
            }
        }
    }

    /// Registering failed (no push entitlement, no network on first run…): local notifications stay.
    var registrationFailureHandler: (() -> Void)?

    /// A silent push arrived: pull what changed. Cleared notifications are already off by then.
    var silentPushHandler: (() async -> Void)? {
        didSet {
            if silentPushWaiting, let silentPushHandler {
                silentPushWaiting = false
                Task { await silentPushHandler() }
            }
        }
    }

    private var waiting: [Action] = []
    private var lastToken: Data?
    private var silentPushWaiting = false

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Push

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        lastToken = deviceToken
        if let tokenHandler {
            Task { await tokenHandler(deviceToken) }
        }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: any Error) {
        registrationFailureHandler?()
    }

    /// The server's silent push (`content-available`): `clear_ids` are notifications read or deleted
    /// on another device, so they come off this one, the badge follows, and a sync brings the state.
    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let ids = userInfo["clear_ids"] as? [String] ?? []
        let aps = userInfo["aps"] as? [String: Any]
        let badge = aps?["badge"] as? Int
        let center = UNUserNotificationCenter.current()
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            let wanted = Set(ids)
            let delivered = await center.deliveredNotifications().filter { notification in
                let request = notification.request
                let carried = request.content.userInfo[ReminderScheduler.notificationKey] as? String
                return wanted.contains(request.identifier) || carried.map(wanted.contains) == true
            }
            center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier))
        }
        if let badge {
            try? await center.setBadgeCount(badge)
        }
        if let silentPushHandler {
            await silentPushHandler()
        } else {
            silentPushWaiting = true
        }
        return .newData
    }

    // MARK: - Notifications

    /// Notifications also show while the app is open, as banners.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let info = request.content.userInfo
        // A pushed notification's identifier is its collapse id, which is the notification's id.
        let notificationID = LedgerNotification.id(in: info) ?? (request.identifier.contains(":") ? request.identifier : nil)
        switch response.actionIdentifier {
        case ReminderScheduler.confirmAction:
            guard let text = info[ReminderScheduler.transactionKey] as? String, let id = UUID(uuidString: text) else { return }
            enqueue(.confirm(id, notificationID: notificationID))
        case ReminderScheduler.postponeAction:
            enqueue(.postpone(request.content, identifier: request.identifier))
        case UNNotificationDefaultActionIdentifier:
            var target = LedgerNotification.Target(userInfo: info)
            if target == nil, let text = info[ReminderScheduler.transactionKey] as? String, let id = UUID(uuidString: text) {
                target = .transaction(id)
            }
            enqueue(.open(notificationID: notificationID, target: target))
        default:
            break
        }
    }

    private func enqueue(_ action: Action) {
        waiting.append(action)
        flush()
    }

    private func flush() {
        guard let handler, !waiting.isEmpty else { return }
        let actions = waiting
        waiting = []
        Task {
            for action in actions {
                await handler(action)
            }
        }
    }
}
