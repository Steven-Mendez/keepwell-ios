import Domain
import Foundation

/// Device-local preferences that must not travel with the synced data (the preferred name).
public struct StorePreferences: @unchecked Sendable {
    /// `UserDefaults` is documented as thread-safe; it just isn't marked `Sendable`.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}

extension StorePreferences: ProfileRepository {
    private static let nameKey = "lock.preferredName"

    public func preferredName() async -> String? {
        defaults.string(forKey: Self.nameKey)
    }

    public func setPreferredName(_ name: String?) async {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.nameKey)
        } else {
            defaults.set(trimmed, forKey: Self.nameKey)
        }
    }
}

extension StorePreferences: PendingDeletionStore {
    /// Movement id → when its deletion falls due, kept on this device only: the deletion syncs once written.
    private static let pendingDeletionsKey = "transactions.pendingDeletions"

    public func pendingDeletions() async -> [UUID: Date] {
        let stored = defaults.dictionary(forKey: Self.pendingDeletionsKey) as? [String: Date] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, date in UUID(uuidString: key).map { ($0, date) } })
    }

    public func setPendingDeletions(_ pending: [UUID: Date]) async {
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.pendingDeletionsKey)
        } else {
            defaults.set(Dictionary(uniqueKeysWithValues: pending.map { ($0.uuidString, $1) }), forKey: Self.pendingDeletionsKey)
        }
    }
}
