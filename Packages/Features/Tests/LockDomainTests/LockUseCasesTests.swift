import Domain
import DomainSamples
import Foundation
import Testing
@testable import LockDomain

/// Answers prompts with fixed results and records what was asked.
final class FakeAuthenticator: DeviceAuthenticator, @unchecked Sendable {
    var sensor: Biometry = .faceID
    var biometricsSucceed = true
    var deviceOwnerSucceeds = true
    private(set) var deviceOwnerPrompts: [Bool] = []
    private(set) var biometricPrompts = 0

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

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite("Lockout policy")
struct LockoutPolicyTests {
    @Test
    func theFirstMistakesAreFree() {
        for failures in 0 ..< LockoutPolicy.freeAttempts {
            #expect(LockoutPolicy.lockedUntil(PasscodeAttempts(failures: failures, lastFailure: start), now: start) == nil)
        }
    }

    @Test
    func eachFurtherMistakeWaitsLongerUpToAnHour() {
        let delays = (5 ... 12).map { LockoutPolicy.delay(afterFailures: $0) }
        #expect(delays == [30, 60, 300, 900, 3600, 3600, 3600, 3600])
    }

    @Test
    func theLockoutEndsOnTime() {
        let attempts = PasscodeAttempts(failures: 5, lastFailure: start)
        #expect(LockoutPolicy.lockedUntil(attempts, now: start.addingTimeInterval(29)) == start.addingTimeInterval(30))
        #expect(LockoutPolicy.lockedUntil(attempts, now: start.addingTimeInterval(30)) == nil)
    }

    @Test
    func settingTheClockBackDoesNotStretchTheWait() {
        let attempts = PasscodeAttempts(failures: 5, lastFailure: start)
        let earlier = start.addingTimeInterval(-86400)
        #expect(LockoutPolicy.lockedUntil(attempts, now: earlier) == earlier.addingTimeInterval(30))
    }
}

@Suite("Lock use cases")
struct LockUseCasesTests {
    private func passcode() throws -> Passcode {
        try Passcode("482915")
    }

    @Test
    func theRightPasscodeUnlocksAndForgetsEarlierMistakes() async throws {
        let store = try InMemoryPasscodeStore(passcode: passcode(), attempts: PasscodeAttempts(failures: 3, lastFailure: start))
        let result = await DefaultEnterPasscodeUseCase(passcodes: store) { start }.execute("482915")
        #expect(result == .unlocked)
        #expect(await store.attempts() == .empty)
    }

    @Test
    func wrongPasscodesCountDownThenLockOut() async throws {
        let store = try InMemoryPasscodeStore(passcode: passcode())
        let enter = DefaultEnterPasscodeUseCase(passcodes: store) { start }
        var results: [PasscodeAttemptResult] = []
        for _ in 0 ..< 5 {
            await results.append(enter.execute("000000"))
        }
        #expect(results == [
            .wrong(remainingBeforeLockout: 4),
            .wrong(remainingBeforeLockout: 3),
            .wrong(remainingBeforeLockout: 2),
            .wrong(remainingBeforeLockout: 1),
            .lockedOut(until: start.addingTimeInterval(30)),
        ])
    }

    @Test
    func duringALockoutEvenTheRightPasscodeIsNotChecked() async throws {
        let store = try InMemoryPasscodeStore(passcode: passcode(), attempts: PasscodeAttempts(failures: 5, lastFailure: start))
        let result = await DefaultEnterPasscodeUseCase(passcodes: store) { start.addingTimeInterval(10) }.execute("482915")
        #expect(result == .lockedOut(until: start.addingTimeInterval(30)))
        #expect(await store.attempts().failures == 5)
    }

    @Test
    func theContextReportsPasscodeNameAndLockout() async throws {
        let store = try InMemoryPasscodeStore(
            passcode: passcode(), attempts: PasscodeAttempts(failures: 6, lastFailure: start), name: "Steven",
        )
        let context = await DefaultGetLockContextUseCase(passcodes: store, profile: store) { start }.execute()
        #expect(context == LockContext(hasPasscode: true, preferredName: "Steven", lockedUntil: start.addingTimeInterval(60)))
    }

    @Test
    func faceIDClearsEarlierMistakes() async throws {
        let store = try InMemoryPasscodeStore(passcode: passcode(), attempts: PasscodeAttempts(failures: 5, lastFailure: start))
        let unlock = DefaultUnlockWithDeviceUseCase(authenticator: FakeAuthenticator(), passcodes: store)
        #expect(await unlock.biometrics(reason: "", fallbackTitle: ""))
        #expect(await store.attempts() == .empty)
    }

    @Test
    func noSensorMeansNoBiometricPrompt() async {
        let authenticator = FakeAuthenticator()
        authenticator.sensor = .unavailable
        let unlock = DefaultUnlockWithDeviceUseCase(authenticator: authenticator, passcodes: InMemoryPasscodeStore())
        #expect(await !unlock.biometrics(reason: "", fallbackTitle: ""))
        #expect(authenticator.biometricPrompts == 0)
    }

    @Test
    func recoveringWithTheIPhonePasscodeTurnsTheAppPasscodeOff() async throws {
        let store = try InMemoryPasscodeStore(passcode: passcode(), attempts: PasscodeAttempts(failures: 9, lastFailure: start))
        let authenticator = FakeAuthenticator()
        #expect(await DefaultRecoverPasscodeUseCase(authenticator: authenticator, passcodes: store).execute(reason: ""))
        #expect(authenticator.deviceOwnerPrompts == [false])
        #expect(await !store.hasPasscode())
        #expect(await store.attempts() == .empty)
    }

    @Test
    func aFailedRecoveryKeepsThePasscode() async throws {
        let store = try InMemoryPasscodeStore(passcode: passcode())
        let authenticator = FakeAuthenticator()
        authenticator.deviceOwnerSucceeds = false
        #expect(await !DefaultRecoverPasscodeUseCase(authenticator: authenticator, passcodes: store).execute(reason: ""))
        #expect(await store.hasPasscode())
    }

    @Test
    func settingRefusesEasyCodes() async {
        let store = InMemoryPasscodeStore()
        await #expect(throws: DomainError.passcodeTooSimple) {
            try await DefaultSetPasscodeUseCase(passcodes: store).execute("123456")
        }
        #expect(await !store.hasPasscode())
    }

    @Test
    func settingSavesAValidCode() async throws {
        let store = InMemoryPasscodeStore()
        try await DefaultSetPasscodeUseCase(passcodes: store).execute("482915")
        #expect(try await store.verify(Passcode("482915")))
    }
}

@Suite("Day part")
struct DayPartTests {
    @Test(arguments: [
        (4, DayPart.evening),
        (5, .morning),
        (11, .morning),
        (12, .afternoon),
        (18, .afternoon),
        (19, .evening),
        (23, .evening),
    ])
    func greetsByTheHour(hour: Int, expected: DayPart) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: hour)))
        #expect(DayPart(date: date, calendar: calendar) == expected)
    }
}
