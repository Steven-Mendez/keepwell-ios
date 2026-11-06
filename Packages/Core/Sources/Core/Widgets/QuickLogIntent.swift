import AppIntents
import Foundation

/// The quick-log widget's buttons. Small widgets can't hold several links, so each button runs
/// this intent: it leaves the request in the App Group and brings the app forward, which then
/// opens a new expense in that category.
public struct QuickLogIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log expense"
    public static let isDiscoverable = false
    public static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Category")
    public var categoryID: String?

    public init() {}

    public init(categoryID: String?) {
        self.categoryID = categoryID
    }

    public func perform() async throws -> some IntentResult {
        WidgetSnapshotStore().requestQuickLog(categoryID: categoryID)
        return .result()
    }
}
