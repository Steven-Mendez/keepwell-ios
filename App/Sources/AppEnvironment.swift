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

    static let current: AppEnvironment = {
        let info = Bundle.main.infoDictionary ?? [:]
        let container = info["KeepwellCloudKitContainer"] as? String ?? ""
        let arguments = ProcessInfo.processInfo.arguments
        return Self(
            cloudKitContainer: container,
            isUITesting: arguments.contains("-ui-testing"),
            usesSampleData: arguments.contains("-sample-data"),
        )
    }()
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Keepwell", category: "App")
}
