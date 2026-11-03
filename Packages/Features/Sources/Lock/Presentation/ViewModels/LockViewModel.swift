import Foundation
import LockDomain
import Observation

/// The lock screen: the app passcode on a keypad with Face ID or Touch ID on top, or, with no app
/// passcode, the iPhone's own sheet.
@MainActor
@Observable
public final class LockViewModel {
    public enum Mode: Equatable {
        case loading
        /// The app passcode keypad.
        case keypad
        /// No app passcode: biometrics or the iPhone passcode through the system sheet.
        case system
    }

    public private(set) var mode = Mode.loading
    public private(set) var biometry = Biometry.unavailable
    public private(set) var preferredName: String?
    /// Digits typed so far; only their count is shown.
    public private(set) var entered = ""
    /// Showing a rejected entry: red dots and a shake.
    public private(set) var isError = false
    /// Bumped on each rejection, to replay the shake and the error haptic.
    public private(set) var rejections = 0
    public private(set) var message: String?
    public private(set) var lockedUntil: Date?
    public private(set) var isAuthenticating = false
    public private(set) var isUnlocked = false

    /// The person chose "Passcode only" in settings, so biometrics are never offered.
    private let prefersPasscode: Bool
    private let getContext: any GetLockContextUseCase
    private let enterPasscode: any EnterPasscodeUseCase
    private let unlockWithDevice: any UnlockWithDeviceUseCase
    private let recoverPasscode: any RecoverPasscodeUseCase
    private var didAutoPrompt = false

    public init(
        prefersPasscode: Bool,
        getContext: any GetLockContextUseCase,
        enterPasscode: any EnterPasscodeUseCase,
        unlockWithDevice: any UnlockWithDeviceUseCase,
        recoverPasscode: any RecoverPasscodeUseCase,
    ) {
        self.prefersPasscode = prefersPasscode
        self.getContext = getContext
        self.enterPasscode = enterPasscode
        self.unlockWithDevice = unlockWithDevice
        self.recoverPasscode = recoverPasscode
    }

    public var offersBiometrics: Bool {
        !prefersPasscode && biometry != .unavailable
    }

    public func isLockedOut(at date: Date) -> Bool {
        lockedUntil.map { $0 > date } ?? false
    }

    /// Loads the context and asks once on its own: Face ID straight away when it's on, so most
    /// unlocks need no tap; the keypad waits underneath if it fails or is cancelled.
    public func appear() async {
        guard !didAutoPrompt else { return }
        didAutoPrompt = true
        biometry = unlockWithDevice.biometry()
        let context = await getContext.execute()
        preferredName = context.preferredName
        lockedUntil = context.lockedUntil
        mode = context.hasPasscode ? .keypad : .system
        await promptOnItsOwn()
    }

    /// Reopening the app while it's still locked asks again, as on first appearance. Only after
    /// the background: the system prompt itself makes the app inactive, so reacting to every
    /// return to active would loop after a cancel.
    public func returnedFromBackground() async {
        guard didAutoPrompt, !isUnlocked else { return }
        entered = ""
        isError = false
        await promptOnItsOwn()
    }

    private func promptOnItsOwn() async {
        switch mode {
        case .keypad where offersBiometrics: await useBiometrics()
        case .system: await useDevice(allowsBiometrics: offersBiometrics)
        default: break
        }
    }

    public func press(_ digit: Int) async {
        guard mode == .keypad, !isAuthenticating, !isLockedOut(at: .now), (0 ... 9).contains(digit) else { return }
        if isError {
            clearError()
        }
        guard entered.count < LockStrings.passcodeLength else { return }
        entered.append(String(digit))
        guard entered.count == LockStrings.passcodeLength else { return }
        isAuthenticating = true
        let result = await enterPasscode.execute(entered)
        isAuthenticating = false
        switch result {
        case .unlocked:
            message = nil
            isUnlocked = true
        case let .wrong(remaining):
            reject(LockStrings.wrongPasscode(remaining: remaining))
        case let .lockedOut(until):
            lockedUntil = until
            reject(nil)
        }
    }

    public func deleteDigit() {
        if isError {
            clearError()
        } else if !entered.isEmpty {
            entered.removeLast()
        }
    }

    /// Ends the red state after the shake, ready for the next try.
    public func clearError() {
        isError = false
        entered = ""
    }

    public func useBiometrics() async {
        guard offersBiometrics, !isAuthenticating else { return }
        isAuthenticating = true
        let success = await unlockWithDevice.biometrics(reason: LockStrings.reason, fallbackTitle: LockStrings.enterPasscode)
        isAuthenticating = false
        if success {
            lockedUntil = nil
            isUnlocked = true
        }
    }

    /// The system sheet, when there's no app passcode.
    public func useDevice(allowsBiometrics: Bool) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let success = await unlockWithDevice.deviceOwner(reason: LockStrings.reason, allowsBiometrics: allowsBiometrics)
        isAuthenticating = false
        isUnlocked = success
    }

    /// "Forgot your passcode?": the iPhone passcode gets the owner in and removes the app one.
    public func forgotPasscode() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let success = await recoverPasscode.execute(reason: LockStrings.recoveryReason)
        isAuthenticating = false
        if success {
            lockedUntil = nil
            isUnlocked = true
        }
    }

    public func greeting(at date: Date, calendar: Calendar = .current) -> String {
        LockStrings.greeting(DayPart(date: date, calendar: calendar), name: preferredName)
    }

    private func reject(_ message: String?) {
        self.message = message
        isError = true
        rejections += 1
    }
}
