import Foundation
import Persistence

/// Picks the store before the `ModelContainer` exists. Since increment 15 the data lives on the
/// iPhone only, and the Keepwell account syncs it; the file is the one CloudKit used to mirror, so
/// existing data stays where it was.
enum StoreSelector {
    static func store(for environment: AppEnvironment) async -> PersistenceStore {
        environment.isUITesting || environment.usesSampleData ? .inMemory : .local
    }
}
