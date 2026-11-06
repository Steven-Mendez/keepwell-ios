import Domain
import Foundation
import Synchronization
import Testing
@testable import Persistence

/// Stands in for the Keychain, which a package test bundle has no entitlement to reach.
private final class DictionaryStorage: SecureItemStorage {
    private let items = Mutex<[String: Data]>([:])

    func data(for key: String) -> Data? {
        items.withLock { $0[key] }
    }

    func set(_ data: Data, for key: String) {
        items.withLock { $0[key] = data }
    }

    func remove(_ key: String) {
        items.withLock { $0[key] = nil }
    }

    var allData: [Data] {
        items.withLock { Array($0.values) }
    }
}

@Suite("Keychain passcode store")
struct KeychainPasscodeStoreTests {
    private let storage = DictionaryStorage()
    private var store: KeychainPasscodeStore {
        KeychainPasscodeStore(storage: storage, rounds: 1000)
    }

    @Test
    func verifiesOnlyTheSavedPasscode() async throws {
        #expect(await !store.hasPasscode())
        try await store.setPasscode(Passcode("482915"))
        #expect(await store.hasPasscode())
        #expect(try await store.verify(Passcode("482915")))
        #expect(try await !store.verify(Passcode("482916")))
    }

    @Test
    func neverStoresTheDigitsThemselves() async throws {
        try await store.setPasscode(Passcode("482915"))
        let digits = Data("482915".utf8)
        #expect(storage.allData.allSatisfy { !$0.contains(digits) })
    }

    @Test
    func theSameCodeHashesDifferentlyEachTime() async throws {
        try await store.setPasscode(Passcode("482915"))
        let first = try #require(store.stored())
        try await store.setPasscode(Passcode("482915"))
        let second = try #require(store.stored())
        #expect(first.salt != second.salt)
        #expect(first.hash != second.hash)
    }

    @Test
    func removingClearsTheCodeAndTheFailedAttempts() async throws {
        try await store.setPasscode(Passcode("482915"))
        await store.setAttempts(PasscodeAttempts(failures: 3, lastFailure: .now))
        #expect(await store.attempts().failures == 3)
        await store.removePasscode()
        #expect(await !store.hasPasscode())
        #expect(await store.attempts() == .empty)
        #expect(try await !store.verify(Passcode("482915")))
    }

    @Test
    func aNewPasscodeStartsWithNoFailedAttempts() async throws {
        await store.setAttempts(PasscodeAttempts(failures: 7, lastFailure: .now))
        try await store.setPasscode(Passcode("482915"))
        #expect(await store.attempts() == .empty)
    }
}

@Suite("Store preferences as profile")
struct ProfilePreferenceTests {
    @Test
    func keepsATrimmedNameAndForgetsAnEmptyOne() async throws {
        let defaults = try #require(UserDefaults(suiteName: "Profile.\(UUID().uuidString)"))
        let profile: any ProfileRepository = StorePreferences(defaults: defaults)
        #expect(await profile.preferredName() == nil)
        await profile.setPreferredName("  Steven ")
        #expect(await profile.preferredName() == "Steven")
        await profile.setPreferredName("   ")
        #expect(await profile.preferredName() == nil)
    }
}
