import DesignSystem
import OnboardingPresentation
import OSLog
import Persistence
import SwiftData
import SwiftUI

@main
struct KeepwellApp: App {
    @UIApplicationDelegateAdaptor(NotificationResponder.self) private var notifications
    @State private var container: AppContainer?
    /// Set before the first await so a second run of `.task` can't open a second store.
    @State private var isBootstrapping = false

    init() {
        KWFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container, notifications: notifications)
                } else {
                    SplashView()
                }
            }
            .task { await bootstrap() }
        }
    }

    /// Opens the store while the splash shows. The splash stays at least briefly so it reads as
    /// a deliberate screen rather than a flash.
    private func bootstrap() async {
        guard container == nil, !isBootstrapping else { return }
        isBootstrapping = true
        let environment = AppEnvironment.current
        async let minimumSplash: Void = (try? Task.sleep(for: .milliseconds(800))) ?? ()
        let store = await StoreSelector.store(for: environment)
        let made = AppContainer(modelContainer: Self.makeModelContainer(store: store))
        #if DEBUG
        if environment.usesSampleData {
            await made.seedSampleData()
        }
        #endif
        await made.normalizeBankCards()
        await made.materializeRecurring()
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
