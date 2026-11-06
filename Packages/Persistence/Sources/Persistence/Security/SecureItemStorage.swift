import Foundation
import Security

/// Small secrets by key. The Keychain in the app; a dictionary in tests, which can't reach it.
public protocol SecureItemStorage: Sendable {
    func data(for key: String) -> Data?
    func set(_ data: Data, for key: String)
    func remove(_ key: String)
}

/// Generic-password items that never leave this iPhone: not in iCloud Keychain, not in an
/// encrypted backup restored elsewhere, and unreadable while the device is locked.
public struct KeychainItemStorage: SecureItemStorage {
    private let service: String

    public init(service: String = "com.stevenmendez.keepwell.lock") {
        self.service = service
    }

    public func data(for key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func set(_ data: Data, for key: String) {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return }
        SecItemAdd(baseQuery(key).merging(attributes) { $1 } as CFDictionary, nil)
    }

    public func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
