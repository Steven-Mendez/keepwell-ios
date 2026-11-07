import Foundation

public struct TransactionCategory: Identifiable, Hashable, Sendable, Codable {
    /// A stable slug, separate from `name`, so renaming a category doesn't orphan its history.
    public let id: String
    public let name: String
    public let kind: TransactionKind
    /// The symbol the person picked. Defaults leave it `nil` until then and take theirs from the
    /// id, so a new app version can improve them without migrating data.
    public let icon: String?
    /// A key into the category palette; `nil` falls back to the id's own color.
    public let color: String?
    /// Whether the person gave a default their own name. Until they do, `name` is the shipped
    /// English text and screens translate it by id; afterwards it is shown exactly as typed.
    /// Always `false` for categories the person created, whose name is theirs from the start.
    public let isRenamed: Bool
    /// How much the person means to spend in this category each month. Only expense categories
    /// carry one. It stays in the principal currency in force when it was set: if the person
    /// changes their principal later the budget is ignored rather than converted, because a rate
    /// picked today would silently move the line they drew.
    public let monthlyBudget: Money?

    public init(
        id: String,
        name: String,
        kind: TransactionKind,
        icon: String? = nil,
        color: String? = nil,
        isRenamed: Bool = false,
        monthlyBudget: Money? = nil,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.icon = icon
        self.color = color
        self.isRenamed = isRenamed
        self.monthlyBudget = monthlyBudget
    }

    /// Backups written before defaults could be renamed have no `isRenamed`, and those written
    /// before budgets have no `monthlyBudget`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(TransactionKind.self, forKey: .kind)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        isRenamed = try container.decodeIfPresent(Bool.self, forKey: .isRenamed) ?? false
        monthlyBudget = try container.decodeIfPresent(Money.self, forKey: .monthlyBudget)
    }

    /// Shipped with the app. The person can still rename, restyle or delete it, and bring it
    /// back with "Restore default categories".
    public var isDefault: Bool {
        Self.shipped(id: id) != nil
    }

    /// "Other" and "Other income" receive the movements of a deleted category, so they can be
    /// renamed but never deleted.
    public var isFallback: Bool {
        id == Self.otherExpenseID || id == Self.otherIncomeID
    }

    /// Shows the person's name as-is once they renamed a default; until then it still translates.
    public var translatesByID: Bool {
        isDefault && !isRenamed
    }

    /// The shipped version of a default, which "Restore default categories" brings back.
    public static func shipped(id: String) -> Self? {
        defaults.first { $0.id == id }
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
        ("loan-payments", "Loan payments"), ("other-expense", "Other"),
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
    /// Where a loan's "Pay installment" files the expense unless the person picks another.
    public static let loanPaymentsID = "loan-payments"

    public static func otherID(for kind: TransactionKind) -> String {
        kind == .income ? otherIncomeID : otherExpenseID
    }

    /// The order screens list categories in: per kind, in the order the repository keeps (the
    /// person's own arrangement, or shipped defaults then created ones), with the catch-all
    /// "Other" last so it never hides theirs.
    public static func ordered(_ categories: [Self]) -> [Self] {
        [TransactionKind.expense, .income, .transfer].flatMap { kind in
            let ofKind = categories.filter { $0.kind == kind }
            return ofKind.filter { !$0.isFallback } + ofKind.filter(\.isFallback)
        }
    }
}
