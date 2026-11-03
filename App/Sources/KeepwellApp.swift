import DesignSystem
import OnboardingPresentation
import OSLog
import Persistence
import SwiftData
import SwiftUI

@main
struct KeepwellApp: App {
    @State private var container: AppContainer?

    init() {
        KWFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container)
                } else {
                    SplashView()
                }
            }
            .preferredColorScheme(.dark)
            .task { await bootstrap() }
        }
    }

    /// Opens the store while the splash shows. The splash stays at least briefly so it reads as
    /// a deliberate screen rather than a flash.
    private func bootstrap() async {
        guard container == nil else { return }
        let environment = AppEnvironment.current
        async let minimumSplash: Void = (try? Task.sleep(for: .milliseconds(800))) ?? ()
        let store = await StoreSelector.store(for: environment)
        let made = AppContainer(modelContainer: Self.makeModelContainer(store: store))
        #if DEBUG
        if environment.usesSampleData {
            await made.seedSampleData()
        }
        #endif
        await minimumSplash
        container = made
    }

    private static func makeModelContainer(store: PersistenceStore) -> ModelContainer {
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
