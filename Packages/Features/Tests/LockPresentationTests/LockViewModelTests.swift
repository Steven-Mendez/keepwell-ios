import Domain
import DomainSamples
import Foundation
import LockDomain
import Testing
@testable import LockPresentation

final class StubAuthenticator: DeviceAuthenticator, @unchecked Sendable {
    var sensor: Biometry = .faceID
    var biometricsSucceed = false
    var deviceOwnerSucceeds = true
    private(set) var biometricPrompts = 0
    private(set) var deviceOwnerPrompts: [Bool] = []

    func biometry() -> Biometry {
        sensor
    }

    func authenticate(reason _: String, allowsBiometrics: Bool) async -> Bool {
        deviceOwnerPrompts.append(allowsBiometrics)
        return deviceOwnerSucceeds
    }

    func authenticateWithBiometrics(reason _: String, fallbackTitle _: String) async -> Bool {
        biometricPrompts += 1
        return biometricsSucceed
    }
}

@MainActor
@Suite("Lock view model")
struct LockViewModelTests {
    private let authenticator = StubAuthenticator()

    private func makeViewModel(store: InMemoryPasscodeStore, prefersPasscode: Bool = false) -> LockViewModel {
        LockViewModel(
            prefersPasscode: prefersPasscode,
            getContext: DefaultGetLockContextUseCase(passcodes: store, profile: store),
            enterPasscode: DefaultEnterPasscodeUseCase(passcodes: store),
            unlockWithDevice: DefaultUnlockWithDeviceUseCase(authenticator: authenticator, passcodes: store),
            recoverPasscode: DefaultRecoverPasscodeUseCase(authenticator: authenticator, passcodes: store),
        )
    }

    private func type(_ digits: String, into viewModel: LockViewModel) async {
        for digit in digits.compactMap(\.wholeNumberValue) {
            await viewModel.press(digit)
        }
    }

    @Test
    func withAPasscodeItPromptsFaceIDOnceAndKeepsTheKeypadIfCancelled() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        await viewModel.appear()
        #expect(viewModel.mode == .keypad)
        #expect(authenticator.biometricPrompts == 1)
        #expect(!viewModel.isUnlocked)
    }

    @Test
    func reopeningTheAppAsksForFaceIDAgain() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        await type("48", into: viewModel)
        await viewModel.returnedFromBackground()
        #expect(authenticator.biometricPrompts == 2)
        #expect(viewModel.entered.isEmpty)
    }

    @Test
    func faceIDUnlocks() async throws {
        authenticator.biometricsSucceed = true
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        #expect(viewModel.isUnlocked)
    }

    @Test
    func passcodeOnlyNeverOffersFaceID() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")), prefersPasscode: true)
        await viewModel.appear()
        #expect(!viewModel.offersBiometrics)
        #expect(authenticator.biometricPrompts == 0)
    }

    @Test
    func theRightPasscodeUnlocks() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        await type("482915", into: viewModel)
        #expect(viewModel.isUnlocked)
    }

    @Test
    func aWrongPasscodeShakesAndSaysHowManyTriesAreLeft() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        await type("111111", into: viewModel)
        #expect(viewModel.isError)
        #expect(viewModel.rejections == 1)
        #expect(viewModel.message == "Wrong passcode. 4 tries left.")
        #expect(!viewModel.isUnlocked)
        await viewModel.press(4)
        #expect(!viewModel.isError)
        #expect(viewModel.entered == "4")
    }

    @Test
    func theFifthMistakeLocksTheKeypad() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        for _ in 0 ..< 5 {
            await type("111111", into: viewModel)
            viewModel.clearError()
        }
        #expect(viewModel.isLockedOut(at: .now))
        await type("482915", into: viewModel)
        #expect(!viewModel.isUnlocked)
        #expect(viewModel.entered.isEmpty)
    }

    @Test
    func deleteRemovesTheLastDigit() async throws {
        let viewModel = try makeViewModel(store: InMemoryPasscodeStore(passcode: Passcode("482915")))
        await viewModel.appear()
        await type("48", into: viewModel)
        viewModel.deleteDigit()
        #expect(viewModel.entered == "4")
    }

    @Test
    func withoutAPasscodeItUsesTheSystemSheet() async {
        let viewModel = makeViewModel(store: InMemoryPasscodeStore())
        await viewModel.appear()
        #expect(viewModel.mode == .system)
        #expect(authenticator.deviceOwnerPrompts == [true])
        #expect(viewModel.isUnlocked)
    }

    @Test
    func forgettingThePasscodeUnlocksWithTheIPhonePasscode() async throws {
        let store = try InMemoryPasscodeStore(passcode: Passcode("482915"))
        let viewModel = makeViewModel(store: store)
        await viewModel.appear()
        await viewModel.forgotPasscode()
        #expect(viewModel.isUnlocked)
        #expect(await !store.hasPasscode())
    }

    @Test
    func theGreetingUsesTheNameWhenKnown() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9)))
        let named = makeViewModel(store: InMemoryPasscodeStore(name: "Steven"))
        await named.appear()
        #expect(named.greeting(at: morning, calendar: calendar) == "Good morning, Steven")
        let anonymous = makeViewModel(store: InMemoryPasscodeStore())
        await anonymous.appear()
        #expect(anonymous.greeting(at: morning, calendar: calendar) == "Good morning")
    }
}

@MainActor
@Suite("Passcode setup view model")
struct PasscodeSetupViewModelTests {
    private let store = InMemoryPasscodeStore()

    private func type(_ digits: String, into viewModel: PasscodeSetupViewModel) async {
        for digit in digits.compactMap(\.wholeNumberValue) {
            await viewModel.press(digit)
        }
    }

    @Test
    func typingTheSameCodeTwiceSavesIt() async throws {
        let viewModel = PasscodeSetupViewModel(setPasscode: DefaultSetPasscodeUseCase(passcodes: store))
        await type("482915", into: viewModel)
        #expect(viewModel.step == .confirm)
        #expect(viewModel.entered.isEmpty)
        await type("482915", into: viewModel)
        #expect(viewModel.isSaved)
        #expect(try await store.verify(Passcode("482915")))
    }

    @Test
    func aMismatchStartsOver() async {
        let viewModel = PasscodeSetupViewModel(setPasscode: DefaultSetPasscodeUseCase(passcodes: store))
        await type("482915", into: viewModel)
        await type("482916", into: viewModel)
        #expect(viewModel.step == .create)
        #expect(viewModel.isError)
        #expect(viewModel.message == "The passcodes didn't match. Start again.")
        #expect(await !store.hasPasscode())
    }

    @Test
    func anEasyCodeIsRefusedBeforeConfirming() async {
        let viewModel = PasscodeSetupViewModel(setPasscode: DefaultSetPasscodeUseCase(passcodes: store))
        await type("111111", into: viewModel)
        #expect(viewModel.step == .create)
        #expect(viewModel.isError)
        #expect(viewModel.rejections == 1)
    }
}
