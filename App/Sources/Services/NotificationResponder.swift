import UIKit
import UserNotifications

/// Receives taps on notification actions ("Confirm", "Postpone"). iOS can deliver one before the
/// store has opened, so actions wait until the root view installs its handler.
@MainActor
final class NotificationResponder: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    enum Action {
        case confirm(UUID)
        case postpone(UNNotificationContent, identifier: String)
    }

    var handler: ((Action) async -> Void)? {
        didSet { flush() }
    }

    private var waiting: [Action] = []

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Reminders also show while the app is open, as banners.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        switch response.actionIdentifier {
        case ReminderScheduler.confirmAction:
            guard let text = request.content.userInfo[ReminderScheduler.transactionKey] as? String,
                  let id = UUID(uuidString: text)
            else { return }
            enqueue(.confirm(id))
        case ReminderScheduler.postponeAction:
            enqueue(.postpone(request.content, identifier: request.identifier))
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
