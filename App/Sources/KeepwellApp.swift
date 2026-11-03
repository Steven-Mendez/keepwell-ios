import DesignSystem
import OSLog
import Persistence
import SwiftData
import SwiftUI

@main
struct KeepwellApp: App {
    private let container: AppContainer

    init() {
        KWFonts.register()
        container = AppContainer(modelContainer: Self.makeModelContainer())
        #if DEBUG
        if AppEnvironment.current.usesSampleData {
            container.seedSampleData()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .preferredColorScheme(.dark)
        }
    }

    /// CloudKit when backup is on, local otherwise; in memory for UI tests and sample runs.
    /// Falls back to on-device storage when CloudKit is unavailable (e.g. a build without a
    /// signing team).
    private static func makeModelContainer() -> ModelContainer {
        let environment = AppEnvironment.current
        let store = environment.isUITesting || environment.usesSampleData
            ? PersistenceStore.inMemory
            : StorePreferences().store(cloudKitContainer: environment.cloudKitContainer)
        do {
            return try ModelContainerFactory.make(store: store)
        } catch {
            Logger.app.error("Store \(String(describing: store), privacy: .public) unavailable, using local: \(error, privacy: .public)")
            do {
                return try ModelContainerFactory.make(store: .local)
            } catch {
                fatalError("Could not create the ModelContainer: \(error)")
            }
        }
    }
}
