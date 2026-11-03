import Foundation
import OSLog

/// Runtime environment read from Info.plist (values injected by the .xcconfig files).
struct AppEnvironment {
    let cloudKitContainer: String
    let isUITesting: Bool

    static let current: AppEnvironment = {
        let info = Bundle.main.infoDictionary ?? [:]
        let container = info["KeepwellCloudKitContainer"] as? String ?? ""
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        return Self(cloudKitContainer: container, isUITesting: isUITesting)
    }()
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Keepwell", category: "App")
}
