import Domain
import Foundation

/// Reads what the lock screen shows: keypad or not, the greeting's name and any lockout.
public protocol GetLockContextUseCase: Sendable {
    func execute() async -> LockContext
}

public struct DefaultGetLockContextUseCase: GetLockContextUseCase {
    private let passcodes: any PasscodeRepository
    private let profile: any ProfileRepository
    private let now: @Sendable () -> Date

    public init(passcodes: any PasscodeRepository, profile: any ProfileRepository, now: @escaping @Sendable () -> Date = { .now }) {
        self.passcodes = passcodes
        self.profile = profile
        self.now = now
    }

    public func execute() async -> LockContext {
        let hasPasscode = await passcodes.hasPasscode()
        return await LockContext(
            hasPasscode: hasPasscode,
            preferredName: profile.preferredName(),
            lockedUntil: hasPasscode ? LockoutPolicy.lockedUntil(passcodes.attempts(), now: now()) : nil,
        )
    }
}

/// Checks a typed passcode, counting mistakes towards the lockout.
public protocol EnterPasscodeUseCase: Sendable {
    func execute(_ digits: String) async -> PasscodeAttemptResult
}

public struct DefaultEnterPasscodeUseCase: EnterPasscodeUseCase {
    private let passcodes: any PasscodeRepository
    private let now: @Sendable () -> Date

    public init(passcodes: any PasscodeRepository, now: @escaping @Sendable () -> Date = { .now }) {
        self.passcodes = passcodes
        self.now = now
    }

    public func execute(_ digits: String) async -> PasscodeAttemptResult {
        let date = now()
        var attempts = await passcodes.attempts()
        if let until = LockoutPolicy.lockedUntil(attempts, now: date) {
            return .lockedOut(until: until)
        }
        if let passcode = try? Passcode(digits), await passcodes.verify(passcode) {
            await passcodes.setAttempts(.empty)
            return .unlocked
        }
        attempts.failures += 1
        attempts.lastFailure = date
        await passcodes.setAttempts(attempts)
        if let until = LockoutPolicy.lockedUntil(attempts, now: date) {
            return .lockedOut(until: until)
        }
        return .wrong(remainingBeforeLockout: LockoutPolicy.freeAttempts - attempts.failures)
    }
}

/// Unlocks with what the device itself knows: Face ID or Touch ID, or the iPhone passcode.
public protocol UnlockWithDeviceUseCase: Sendable {
    func biometry() -> Biometry
    /// Biometrics only; `false` leaves the person on the keypad.
    func biometrics(reason: String, fallbackTitle: String) async -> Bool
    /// The system's own sheet, for when there is no app passcode.
    func deviceOwner(reason: String, allowsBiometrics: Bool) async -> Bool
}

public struct DefaultUnlockWithDeviceUseCase: UnlockWithDeviceUseCase {
    private let authenticator: any DeviceAuthenticator
    private let passcodes: any PasscodeRepository

    public init(authenticator: any DeviceAuthenticator, passcodes: any PasscodeRepository) {
        self.authenticator = authenticator
        self.passcodes = passcodes
    }

    public func biometry() -> Biometry {
        authenticator.biometry()
    }

    public func biometrics(reason: String, fallbackTitle: String) async -> Bool {
        guard authenticator.biometry() != .unavailable,
              await authenticator.authenticateWithBiometrics(reason: reason, fallbackTitle: fallbackTitle)
        else { return false }
        // The owner proved it's them, so earlier typos no longer count towards a lockout.
        await passcodes.setAttempts(.empty)
        return true
    }

    public func deviceOwner(reason: String, allowsBiometrics: Bool) async -> Bool {
        await authenticator.authenticate(reason: reason, allowsBiometrics: allowsBiometrics)
    }
}

/// "Forgot your passcode?": whoever knows the iPhone passcode owns the device, so proving that
/// removes the app passcode (and any lockout) instead of leaving the person locked out of their
/// own data. They can set a new one in Settings.
public protocol RecoverPasscodeUseCase: Sendable {
    func execute(reason: String) async -> Bool
}

public struct DefaultRecoverPasscodeUseCase: RecoverPasscodeUseCase {
    private let authenticator: any DeviceAuthenticator
    private let passcodes: any PasscodeRepository

    public init(authenticator: any DeviceAuthenticator, passcodes: any PasscodeRepository) {
        self.authenticator = authenticator
        self.passcodes = passcodes
    }

    public func execute(reason: String) async -> Bool {
        guard await authenticator.authenticate(reason: reason, allowsBiometrics: false) else { return false }
        await passcodes.removePasscode()
        return true
    }
}

/// Saves a new app passcode once it's been typed twice.
public protocol SetPasscodeUseCase: Sendable {
    func execute(_ digits: String) async throws(DomainError)
}

public struct DefaultSetPasscodeUseCase: SetPasscodeUseCase {
    private let passcodes: any PasscodeRepository

    public init(passcodes: any PasscodeRepository) {
        self.passcodes = passcodes
    }

    public func execute(_ digits: String) async throws(DomainError) {
        let passcode = try Passcode(digits)
        guard !passcode.isTooSimple else { throw .passcodeTooSimple }
        try await passcodes.setPasscode(passcode)
    }
}
