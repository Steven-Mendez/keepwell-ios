import Domain
import Foundation
import LockDomain
import Observation

/// Creating or changing the app passcode: type it, then type it again to confirm.
@MainActor
@Observable
public final class PasscodeSetupViewModel {
    public enum Step: Equatable {
        case create
        case confirm
    }

    public private(set) var step = Step.create
    public private(set) var entered = ""
    public private(set) var isError = false
    public private(set) var rejections = 0
    public private(set) var message: String?
    public private(set) var isSaving = false
    public private(set) var isSaved = false

    private let setPasscode: any SetPasscodeUseCase
    private var firstEntry = ""

    public init(setPasscode: any SetPasscodeUseCase) {
        self.setPasscode = setPasscode
    }

    public func press(_ digit: Int) async {
        guard !isSaving, !isSaved, (0 ... 9).contains(digit) else { return }
        if isError {
            clearError()
        }
        guard entered.count < Passcode.length else { return }
        entered.append(String(digit))
        guard entered.count == Passcode.length else { return }
        switch step {
        case .create:
            // Checked before confirming, so the person doesn't type a code twice only to be told no.
            if (try? Passcode(entered))?.isTooSimple == true {
                reject(String(
                    localized: "That passcode is easy to guess. Try one without repeated or consecutive digits.",
                    bundle: #bundle,
                ))
                return
            }
            firstEntry = entered
            entered = ""
            message = nil
            step = .confirm
        case .confirm:
            guard entered == firstEntry else {
                firstEntry = ""
                step = .create
                reject(String(localized: "The passcodes didn't match. Start again.", bundle: #bundle))
                return
            }
            isSaving = true
            do {
                try await setPasscode.execute(entered)
                isSaved = true
            } catch {
                firstEntry = ""
                step = .create
                reject(String(localized: "We couldn't save the passcode. Try again.", bundle: #bundle))
            }
            isSaving = false
        }
    }

    public func deleteDigit() {
        if isError {
            clearError()
        } else if !entered.isEmpty {
            entered.removeLast()
        }
    }

    public func clearError() {
        isError = false
        entered = ""
    }

    private func reject(_ message: String) {
        self.message = message
        isError = true
        rejections += 1
    }
}
