import CloudKit
import Foundation
import Persistence

/// Picks the store before the `ModelContainer` exists. CloudKit mirroring only starts when the
/// device has an iCloud account; without one (a fresh simulator, a signed-out iPhone) Core Data
/// logs a setup failure and retries for nothing, so the local store is used until next launch.
enum StoreSelector {
    static func store(for environment: AppEnvironment, preferences: StorePreferences = StorePreferences()) async -> PersistenceStore {
        if environment.isUITesting || environment.usesSampleData {
            return .inMemory
        }
        let preferred = preferences.store(cloudKitContainer: environment.cloudKitContainer)
        guard case let .cloudKit(identifier) = preferred else { return preferred }
        // Asking for a container the app isn't signed for stops the app at once, so builds signed
        // without iCloud (free developer accounts allow none) keep data on the device instead.
        guard SigningEntitlements.current.allowsCloudKit(container: identifier) else { return .local }
        let status = try? await CKContainer(identifier: identifier).accountStatus()
        return status == .available ? preferred : .local
    }
}

/// The iCloud containers the installed build was signed for, read from its provisioning profile.
/// App Store and TestFlight builds carry no profile; they are always signed as configured.
struct SigningEntitlements {
    private let containers: [String]?

    static let current = Self(profile: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"))

    init(profile url: URL?) {
        containers = url.flatMap { try? Data(contentsOf: $0) }.flatMap(Self.containers(inProfile:))
    }

    func allowsCloudKit(container: String) -> Bool {
        guard let containers else { return true }
        return containers.contains(container) || containers.contains("*")
    }

    /// The profile is a signed envelope around a plain property list; only the list is needed.
    static func containers(inProfile data: Data) -> [String]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound ..< end.upperBound], format: nil),
              let entitlements = (plist as? [String: Any])?["Entitlements"] as? [String: Any]
        else { return nil }
        return entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
    }
}
