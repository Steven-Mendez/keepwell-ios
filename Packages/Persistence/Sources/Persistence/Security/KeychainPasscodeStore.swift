import CommonCrypto
import CryptoKit
import Domain
import Foundation

/// The app passcode as a salted PBKDF2-SHA256 hash in the Keychain. Six digits are only a million
/// combinations, so the slow hash is what makes trying them all from a copied item expensive; the
/// Keychain's this-device-only protection keeps the item off other devices in the first place.
public struct KeychainPasscodeStore: PasscodeRepository {
    struct Hashed: Codable, Equatable {
        let salt: Data
        let hash: Data
        let rounds: Int
    }

    private static let passcodeKey = "passcode"
    private static let attemptsKey = "attempts"
    private let storage: any SecureItemStorage
    private let rounds: Int

    /// `rounds` is lowered only by tests, which would otherwise spend seconds hashing.
    public init(storage: any SecureItemStorage = KeychainItemStorage(), rounds: Int = 210_000) {
        self.storage = storage
        self.rounds = rounds
    }

    public func hasPasscode() async -> Bool {
        stored() != nil
    }

    public func setPasscode(_ passcode: Passcode) async throws(DomainError) {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        guard let hash = Self.derive(passcode.digits, salt: salt, rounds: rounds) else {
            throw .persistence("Passcode could not be hashed")
        }
        guard let data = try? JSONEncoder().encode(Hashed(salt: salt, hash: hash, rounds: rounds)) else {
            throw .persistence("Passcode could not be encoded")
        }
        storage.set(data, for: Self.passcodeKey)
        storage.remove(Self.attemptsKey)
    }

    public func verify(_ passcode: Passcode) async -> Bool {
        guard let stored = stored(), let hash = Self.derive(passcode.digits, salt: stored.salt, rounds: stored.rounds) else {
            return false
        }
        // Constant-time, so how long a wrong guess takes says nothing about how close it was.
        return SymmetricKey(data: hash) == SymmetricKey(data: stored.hash)
    }

    public func removePasscode() async {
        storage.remove(Self.passcodeKey)
        storage.remove(Self.attemptsKey)
    }

    public func attempts() async -> PasscodeAttempts {
        storage.data(for: Self.attemptsKey).flatMap { try? JSONDecoder().decode(PasscodeAttempts.self, from: $0) } ?? .empty
    }

    public func setAttempts(_ attempts: PasscodeAttempts) async {
        guard let data = try? JSONEncoder().encode(attempts) else { return }
        storage.set(data, for: Self.attemptsKey)
    }

    func stored() -> Hashed? {
        storage.data(for: Self.passcodeKey).flatMap { try? JSONDecoder().decode(Hashed.self, from: $0) }
    }

    private static func derive(_ digits: String, salt: Data, rounds: Int) -> Data? {
        let password = Array(digits.utf8).map { Int8(bitPattern: $0) }
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    output.bindMemory(to: UInt8.self).baseAddress,
                    32,
                )
            }
        }
        return status == kCCSuccess ? derived : nil
    }
}
