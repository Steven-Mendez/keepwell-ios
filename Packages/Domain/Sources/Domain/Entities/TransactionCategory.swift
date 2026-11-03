import Foundation

public struct TransactionCategory: Identifiable, Hashable, Sendable, Codable {
    /// A stable slug, separate from `name`, so renaming a category doesn't orphan its history.
    public let id: String
    public let name: String
    public let kind: TransactionKind

    public init(id: String, name: String, kind: TransactionKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

extension TransactionCategory {
    /// Initial set from HANDOFF → "Categories". The names are the English source text and the
    /// stored default; screens show a localized name by `id` while the stored name is unchanged.
    public static let defaultExpense: [Self] = [
        ("groceries", "Groceries"), ("restaurants", "Restaurants"), ("transport", "Transport"),
        ("housing", "Housing"), ("utilities", "Utilities"), ("health", "Health"), ("education", "Education"),
        ("leisure", "Leisure"), ("shopping", "Shopping"), ("subscriptions", "Subscriptions"),
        ("personal-care", "Personal care"), ("family", "Family"), ("travel", "Travel"),
        ("fees", "Fees"), ("tools", "Tools"), ("other-expense", "Other"),
    ].map { Self(id: $0.0, name: $0.1, kind: .expense) }

    public static let defaultIncome: [Self] = [
        ("salary", "Salary"), ("extra", "Extra"), ("interest", "Interest"),
        ("refunds", "Refunds"), ("other-income", "Other income"),
    ].map { Self(id: $0.0, name: $0.1, kind: .income) }

    public static var defaults: [Self] {
        defaultExpense + defaultIncome
    }

    /// Where reconciliation adjustments and uncategorized imports land.
    public static let otherExpenseID = "other-expense"
    public static let otherIncomeID = "other-income"
}
