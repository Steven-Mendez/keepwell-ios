import Domain
import Foundation

/// Passcode and name kept in memory, for previews and tests. Unlike the Keychain store it keeps
/// the code itself, which is fine for data that never leaves the process.
public actor InMemoryPasscodeStore: PasscodeRepository, ProfileRepository {
    private var passcode: Passcode?
    private var currentAttempts: PasscodeAttempts
    private var name: String?

    public init(passcode: Passcode? = nil, attempts: PasscodeAttempts = .empty, name: String? = nil) {
        self.passcode = passcode
        currentAttempts = attempts
        self.name = name
    }

    public func hasPasscode() -> Bool {
        passcode != nil
    }

    public func setPasscode(_ passcode: Passcode) {
        self.passcode = passcode
        currentAttempts = .empty
    }

    public func verify(_ passcode: Passcode) -> Bool {
        self.passcode == passcode
    }

    public func removePasscode() {
        passcode = nil
        currentAttempts = .empty
    }

    public func attempts() -> PasscodeAttempts {
        currentAttempts
    }

    public func setAttempts(_ attempts: PasscodeAttempts) {
        currentAttempts = attempts
    }

    public func preferredName() -> String? {
        name
    }

    public func setPreferredName(_ name: String?) {
        self.name = name
    }
}
