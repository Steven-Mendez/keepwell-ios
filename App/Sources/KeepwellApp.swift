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
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .preferredColorScheme(.dark)
        }
    }

    /// CloudKit in the real app; in-memory for UI tests. Falls back to on-device storage when
    /// CloudKit is unavailable (e.g. a build without a signing team).
    private static func makeModelContainer() -> ModelContainer {
        let environment = AppEnvironment.current
        let store: PersistenceStore = environment.isUITesting
            ? .inMemory
            : .cloudKit(containerIdentifier: environment.cloudKitContainer)
        do {
            return try ModelContainerFactory.make(store: store)
        } catch {
            Logger.app.error("CloudKit unavailable, falling back to local storage: \(error, privacy: .public)")
            do {
                return try ModelContainerFactory.make(store: .local)
            } catch {
                fatalError("Could not create the ModelContainer: \(error)")
            }
        }
    }
}
