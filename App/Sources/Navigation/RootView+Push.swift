import Domain
import HomePresentation
import SwiftUI

extension RootView {
    // MARK: - Notifications and push

    /// Straight to the store, not through home: a tap can arrive before the screens exist.
    func markRead(_ notificationID: String?) async {
        guard let notificationID else { return }
        try? await container.makeChangeNotifications().execute(.markRead, ids: [notificationID])
        await screens?.home.load()
    }

    /// What the account allows: pushes need `cloud_sync`. Still loading says nothing either way, so
    /// launch doesn't switch them off while the session is being read.
    enum PushStatus {
        case unknown
        case allowed
        case notAllowed
    }

    var pushStatus: PushStatus {
        switch container.cloudAccount?.state {
        case let .signedIn(user): user.canSync ? .allowed : .notAllowed
        case .signedOut, nil: .notAllowed
        case .loading: .unknown
        }
    }

    func installPush() {
        notifications.tokenHandler = { token in await container.push?.received(token: token) }
        notifications.registrationFailureHandler = { container.push?.failed() }
        notifications.silentPushHandler = {
            // The pull that follows lands in the store, which reloads home and clears what changed.
            container.cloudAccount?.sync?.trigger(after: 0)
        }
        container.pushChanged = {
            guard let home = screens?.home else { return }
            Task { await container.publish(from: home) }
        }
    }

    func followPush(_ status: PushStatus) {
        switch status {
        case .allowed: container.push?.activate()
        case .notAllowed: container.push?.deactivate()
        case .unknown: break
        }
    }
}
