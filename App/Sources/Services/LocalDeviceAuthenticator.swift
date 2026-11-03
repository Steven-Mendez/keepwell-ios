import LocalAuthentication
import LockDomain
import Security

/// Face ID, Touch ID or the passcode through LocalAuthentication. A new `LAContext` per request,
/// since a context that already succeeded or was cancelled can't prompt again.
struct LocalDeviceAuthenticator: DeviceAuthenticator {
    func biometry() -> Biometry {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .unavailable }
        return switch context.biometryType {
        case .faceID: .faceID
        case .touchID: .touchID
        case .opticID: .opticID
        case .none: .unavailable
        @unknown default: .unavailable
        }
    }

    func authenticate(reason: String, allowsBiometrics: Bool) async -> Bool {
        let context = LAContext()
        // No passcode set at all: there is nothing to unlock with, so the lock can't apply.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        guard allowsBiometrics, biometry() != .unavailable else {
            return await authenticateWithPasscode(reason: reason)
        }
        // The system's fallback button goes to the passcode.
        context.localizedFallbackTitle = String(localized: "Use iPhone passcode")
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            if (error as? LAError)?.code == .userFallback {
                return await authenticateWithPasscode(reason: reason)
            }
            return false
        }
    }

    func authenticateWithBiometrics(reason: String, fallbackTitle: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = fallbackTitle
        // Any failure, the fallback button included, leaves the person on the app's keypad.
        return await (try? context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
    }

    /// The passcode screen alone. `deviceOwnerAuthentication` would try Face ID or Touch ID first;
    /// an access control that only accepts the device passcode asks for nothing else.
    private func authenticateWithPasscode(reason: String) async -> Bool {
        #if targetEnvironment(simulator)
        // The simulator doesn't support access-control evaluation, nor has a passcode to ask for.
        return await evaluateDeviceOwner(reason: reason)
        #else
        guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .devicePasscode, nil) else {
            return await evaluateDeviceOwner(reason: reason)
        }
        do {
            return try await LAContext().evaluateAccessControl(control, operation: .useItem, localizedReason: reason)
        } catch {
            // The person cancelling or getting it wrong stays locked; anything else (the system
            // can't run this check) falls back rather than leaving them with no way in.
            switch (error as? LAError)?.code {
            case .userCancel, .appCancel, .systemCancel, .authenticationFailed: return false
            default: return await evaluateDeviceOwner(reason: reason)
            }
        }
        #endif
    }

    private func evaluateDeviceOwner(reason: String) async -> Bool {
        await (try? LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
