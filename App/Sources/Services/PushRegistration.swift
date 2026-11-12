import CloudAccountDomain
import Foundation
import UIKit

/// Registers this iPhone for the server's pushes (ADR 0012 in keepwell-api) while the account has
/// `cloud_sync`. iOS hands the token over on every launch that asks, so asking at launch, on
/// returning to the app and after signing in also re-registers a token that changed, and the time
/// zone and language the server words and times notifications by.
///
/// While it is registered the server sends everything, so local notifications stop.
@MainActor
final class PushRegistration {
    /// Only the server answering `204` counts: registered means the server has this token.
    static let registeredKey = "keepwell.push.registered"

    private let register: any RegisterPushDeviceUseCase
    private let defaults: UserDefaults
    private var isActive = false

    /// Told when `isRegistered` flips, so local notifications can start or stop.
    var onChange: (() -> Void)?

    private(set) var isRegistered: Bool {
        didSet {
            defaults.set(isRegistered, forKey: Self.registeredKey)
            if oldValue != isRegistered {
                onChange?()
            }
        }
    }

    init(register: any RegisterPushDeviceUseCase, defaults: UserDefaults = .standard) {
        self.register = register
        self.defaults = defaults
        isRegistered = defaults.bool(forKey: Self.registeredKey)
    }

    /// Signed in with `cloud_sync`: ask iOS for the token (again).
    func activate() {
        isActive = true
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Signed out, or the plan lost: the server was told while the session lasted.
    func deactivate() {
        isActive = false
        isRegistered = false
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func received(token: Data) async {
        guard isActive else { return }
        let device = PushDevice(
            token: PushDevice.hex(token),
            timeZone: TimeZone.current.identifier,
            locale: Locale.current.identifier(.bcp47),
            // Debug builds are signed for development; TestFlight and the App Store use production.
            environment: Self.environment,
        )
        do {
            try await register.execute(device)
            isRegistered = true
        } catch {
            // Offline or refused: what was registered before stays true until iOS says otherwise;
            // the next launch tries again.
        }
    }

    /// iOS couldn't register (no entitlement on this build, no network the first time).
    func failed() {
        isRegistered = false
    }

    private static var environment: PushDevice.Environment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}
