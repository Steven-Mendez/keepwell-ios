import Foundation
import OSLog

/// Runtime environment read from Info.plist (values injected by the .xcconfig files) and launch
/// arguments.
struct AppEnvironment {
    let cloudKitContainer: String
    let isUITesting: Bool
    /// `-sample-data`: start from the generic sample set in memory (Debug builds only), for UI
    /// tests and simulator checks against the design.
    let usesSampleData: Bool
    /// `-open-new-movement`: opens the create-movement flow at launch (Debug builds only), so UI
    /// tests can reach it directly.
    let opensNewMovement: Bool
    /// `-force-lock`: shows the lock screen even with sample data (Debug builds only), to check it
    /// on the simulator.
    let forcesLock: Bool
    /// `-reminders-soon`: asks for notification permission and moves every reminder a few seconds
    /// ahead (Debug builds only), to see them arrive on the simulator.
    let remindsSoon: Bool

    static let current: AppEnvironment = {
        let info = Bundle.main.infoDictionary ?? [:]
        let container = info["KeepwellCloudKitContainer"] as? String ?? ""
        let arguments = ProcessInfo.processInfo.arguments
        return Self(
            cloudKitContainer: container,
            isUITesting: arguments.contains("-ui-testing"),
            usesSampleData: arguments.contains("-sample-data"),
            opensNewMovement: arguments.contains("-open-new-movement"),
            forcesLock: arguments.contains("-force-lock"),
            remindsSoon: arguments.contains("-reminders-soon"),
        )
    }()
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Keepwell", category: "App")
}
