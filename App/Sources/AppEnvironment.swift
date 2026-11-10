import Foundation
import OSLog

/// Runtime environment read from Info.plist (values injected by the .xcconfig files) and launch
/// arguments.
struct AppEnvironment {
    /// The Keepwell API (sign-in, sync). `nil` when the build sets no `API_BASE_URL`: the app stays
    /// local-only and Settings shows no account section.
    let apiBaseURL: URL?
    /// Keepwell on the web, whose privacy policy Settings links to; `nil` without an API.
    let privacyPolicyURL: URL?
    /// "1.0.1 (12)", for the foot of Settings.
    let version: String?
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
        let arguments = ProcessInfo.processInfo.arguments
        let api = (info["KeepwellAPIBaseURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let marketing = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        return Self(
            apiBaseURL: api,
            // The API and the web share a host (the web serves the API's routes).
            privacyPolicyURL: api?.appending(path: "privacy"),
            version: marketing.map { version in build.map { "\(version) (\($0))" } ?? version },
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
