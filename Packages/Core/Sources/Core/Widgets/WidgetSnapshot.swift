import Foundation

/// What the home-screen widgets show, written by the app whenever home refreshes and read by the
/// widget extension from the shared App Group. Texts arrive formatted and translated, so the
/// widget never handles money or languages and always matches what the app shows.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public let title: String
        public let value: String

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    /// A one-tap expense in a category ("Groceries").
    public struct Shortcut: Codable, Sendable, Equatable {
        public let categoryID: String
        public let title: String

        public init(categoryID: String, title: String) {
            self.categoryID = categoryID
            self.title = title
        }
    }

    /// "November".
    public let monthTitle: String
    /// "$339.94".
    public let spent: String
    /// "spent · 4 planned".
    public let spentCaption: String
    /// Spending against income, 0…1, for the bar.
    public let spentFraction: Double
    /// "Net worth".
    public let netWorthTitle: String
    public let netWorth: String
    /// "November: you saved 86%".
    public let netWorthCaption: String?
    /// Up to three account balances.
    public let balances: [Line]
    /// "Log quickly".
    public let shortcutsTitle: String
    public let shortcuts: [Shortcut]
    public let updatedAt: Date

    public init(
        monthTitle: String,
        spent: String,
        spentCaption: String,
        spentFraction: Double,
        netWorthTitle: String,
        netWorth: String,
        netWorthCaption: String?,
        balances: [Line],
        shortcutsTitle: String,
        shortcuts: [Shortcut],
        updatedAt: Date,
    ) {
        self.monthTitle = monthTitle
        self.spent = spent
        self.spentCaption = spentCaption
        self.spentFraction = spentFraction
        self.netWorthTitle = netWorthTitle
        self.netWorth = netWorth
        self.netWorthCaption = netWorthCaption
        self.balances = balances
        self.shortcutsTitle = shortcutsTitle
        self.shortcuts = shortcuts
        self.updatedAt = updatedAt
    }
}

/// Reads and writes the snapshot in the App Group both targets share. The group's id comes from
/// each target's Info.plist (`KeepwellAppGroup`), so Debug, Staging and Release stay apart.
public struct WidgetSnapshotStore: Sendable {
    private let suiteName: String?
    private static let key = "widgets.snapshot"

    public init(bundle: Bundle = .main) {
        suiteName = bundle.object(forInfoDictionaryKey: "KeepwellAppGroup") as? String
    }

    /// `UserDefaults` isn't `Sendable`, so each call opens the suite; it's cached by the system.
    private var defaults: UserDefaults? {
        suiteName.flatMap(UserDefaults.init(suiteName:))
    }

    public func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    /// After "Delete all my data", so widgets stop showing old amounts.
    public func clear() {
        defaults?.removeObject(forKey: Self.key)
        defaults?.removeObject(forKey: Self.quickLogKey)
    }

    private static let quickLogKey = "widgets.quickLog"
    /// Stands for "no category" in a request, since the stored value can't be `nil`.
    private static let anyCategory = ""

    /// A widget asked to log an expense; the app picks it up when it comes to the front.
    public func requestQuickLog(categoryID: String?) {
        defaults?.set(categoryID ?? Self.anyCategory, forKey: Self.quickLogKey)
    }

    /// The pending request, once: `.some(nil)` means an expense in no particular category.
    public func takeQuickLogRequest() -> String?? {
        guard let value = defaults?.string(forKey: Self.quickLogKey) else { return nil }
        defaults?.removeObject(forKey: Self.quickLogKey)
        return .some(value == Self.anyCategory ? nil : value)
    }
}

/// The links widgets open: `keepwell://new-expense?category=groceries`.
public enum AppLink {
    public static let scheme = "keepwell"

    /// Opens the app on home, from a widget's background.
    public static var home: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "home"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public static func newExpense(categoryID: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "new-expense"
        components.queryItems = categoryID.map { [URLQueryItem(name: "category", value: $0)] }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// The category of a new-expense link, or `nil` for any other link.
    public static func newExpenseCategory(from url: URL) -> String?? {
        guard url.scheme == scheme, url.host() == "new-expense" else { return nil }
        let category = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "category" }?.value
        return .some(category)
    }
}
