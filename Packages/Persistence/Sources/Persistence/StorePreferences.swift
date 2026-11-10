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
