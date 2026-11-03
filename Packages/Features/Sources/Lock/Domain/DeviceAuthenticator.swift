import Foundation

/// The biometric sensor the device has, which decides the lock screen's icon and wording.
public enum Biometry: Sendable, Equatable {
    case faceID
    case touchID
    case opticID
    /// No sensor enrolled: only the passcode works.
    case unavailable
}

/// Asks the device owner to prove it's them. Implemented with LocalAuthentication in the app, so
/// this layer stays free of system frameworks and can be faked in tests and previews.
public protocol DeviceAuthenticator: Sendable {
    func biometry() -> Biometry
    /// `allowsBiometrics` false goes straight to the passcode ("Use iPhone passcode").
    /// Returns whether the person was authenticated; cancelling is a `false`, not an error.
    func authenticate(reason: String, allowsBiometrics: Bool) async -> Bool
}
