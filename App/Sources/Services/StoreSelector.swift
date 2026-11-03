import CloudKit
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
        let status = try? await CKContainer(identifier: identifier).accountStatus()
        return status == .available ? preferred : .local
    }
}
