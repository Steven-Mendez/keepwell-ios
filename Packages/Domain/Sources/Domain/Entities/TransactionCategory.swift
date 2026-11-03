import Foundation

public struct TransactionCategory: Identifiable, Hashable, Sendable, Codable {
    /// A stable slug, separate from `name`, so renaming a category doesn't orphan its history.
    public let id: String
    public let name: String
    public let kind: TransactionKind
    /// The symbol the person picked for a category they created. Defaults leave it `nil` and take
    /// theirs from the id, so a new app version can improve them without migrating data.
    public let icon: String?
    /// A key into the category palette; `nil` falls back to the id's own color.
    public let color: String?

    public init(id: String, name: String, kind: TransactionKind, icon: String? = nil, color: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.color = color
    }

    /// Defaults ship with the app and can't be deleted: imports, reconciliation and widgets rely on them.
    public var isDefault: Bool {
        Self.defaults.contains { $0.id == id }
    }

    /// Ids of created categories carry a prefix so they can never collide with a default added later.
    public static func newCustomID() -> String {
        "custom-\(UUID().uuidString.lowercased())"
    }
}

extension TransactionCategory {
    /// Initial set from HANDOFF → "Categories", extended with what most finance apps offer. The
    /// names are the English source text and the stored default; screens show a localized name by
    /// `id` while the stored name is unchanged.
    public static let defaultExpense: [Self] = [
        ("groceries", "Groceries"), ("restaurants", "Restaurants"), ("transport", "Transport"),
        ("housing", "Housing"), ("utilities", "Utilities"), ("health", "Health"), ("education", "Education"),
        ("leisure", "Leisure"), ("shopping", "Shopping"), ("subscriptions", "Subscriptions"),
        ("personal-care", "Personal care"), ("family", "Family"), ("travel", "Travel"),
        ("fees", "Fees"), ("tools", "Tools"), ("pets", "Pets"), ("gifts", "Gifts"),
        ("insurance", "Insurance"), ("taxes", "Taxes"), ("savings", "Savings"), ("donations", "Donations"),
        ("other-expense", "Other"),
    ].map { Self(id: $0.0, name: $0.1, kind: .expense) }

    public static let defaultIncome: [Self] = [
        ("salary", "Salary"), ("freelance", "Freelance"), ("extra", "Extra"), ("interest", "Interest"),
        ("investments", "Investments"), ("rental", "Rental"), ("gifts-received", "Gifts received"),
        ("refunds", "Refunds"), ("other-income", "Other income"),
    ].map { Self(id: $0.0, name: $0.1, kind: .income) }

    public static var defaults: [Self] {
        defaultExpense + defaultIncome
    }

    /// Where reconciliation adjustments and uncategorized imports land.
    public static let otherExpenseID = "other-expense"
    public static let otherIncomeID = "other-income"

    public static func otherID(for kind: TransactionKind) -> String {
        kind == .income ? otherIncomeID : otherExpenseID
    }

    /// The order screens list categories in: per kind, the defaults as shipped, then the person's
    /// own in the order they were created, and the catch-all "Other" last so it never hides theirs.
    public static func ordered(_ categories: [Self]) -> [Self] {
        let rank = Dictionary(uniqueKeysWithValues: defaults.enumerated().map { ($0.element.id, $0.offset) })
        let isOther: (Self) -> Bool = { $0.id == otherExpenseID || $0.id == otherIncomeID }
        return [TransactionKind.expense, .income, .transfer].flatMap { kind in
            let ofKind = categories.filter { $0.kind == kind }
            let shipped = ofKind.filter { rank[$0.id] != nil && !isOther($0) }.sorted { rank[$0.id] ?? 0 < rank[$1.id] ?? 0 }
            let created = ofKind.filter { rank[$0.id] == nil }
            return shipped + created + ofKind.filter(isOther)
        }
    }
}
