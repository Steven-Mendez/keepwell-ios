import Foundation
import Security

/// Where the session cookie lives between launches. Better Auth's cookie is the documented way for
/// native clients; it is kept in the Keychain, never in `HTTPCookieStorage` or `UserDefaults`.
public protocol SessionStore: Sendable {
    func load() -> String?
    func save(_ cookie: String)
    func clear()
}

/// Keychain item readable after the first unlock, on this device only: not in backups, not moved
/// to a new iPhone (which signs in again).
public struct KeychainSessionStore: SessionStore {
    private let service: String
    private let account: String

    /// `account` names the item: the session cookie by default, or another value such as the
    /// installation's sync `client_id`.
    public init(service: String, account: String = "session-cookie") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ cookie: String) {
        let data = Data(cookie.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests and previews.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cookie: String?

    public init(cookie: String? = nil) {
        self.cookie = cookie
    }

    public func load() -> String? {
        lock.withLock { cookie }
    }

    public func save(_ cookie: String) {
        lock.withLock { self.cookie = cookie }
    }

    public func clear() {
        lock.withLock { cookie = nil }
    }
}

/// This installation's identity for sync, created on first use and kept in the Keychain (this
/// device only). If it is lost, a new one is made and the engine starts from a snapshot.
public enum SyncClientID {
    public static func load(from store: any SessionStore) -> String {
        if let existing = store.load() {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        store.save(id)
        return id
    }
}
