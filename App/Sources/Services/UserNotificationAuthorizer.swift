import OnboardingDomain
import UserNotifications

/// Asks iOS for alert, badge and sound permission.
struct UserNotificationAuthorizer: NotificationAuthorizing {
    func requestAuthorization() async -> Bool {
        await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }
}
