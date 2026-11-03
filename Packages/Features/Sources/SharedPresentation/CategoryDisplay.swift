import DesignSystem
import Domain
import Foundation
import SwiftUI

/// Name, icon and color of a category. Icons follow the category grid in the create-transaction flow;
/// colors come from the `category` tokens, falling back to `faint` where the tokens define none.
public enum CategoryDisplay {
    public static func icon(for categoryID: String?) -> KWIcon {
        switch categoryID {
        case "restaurants": .restaurant
        case "groceries": .cart
        case "transport": .bus
        case "utilities": .bolt
        case "subscriptions": .subscription
        case "tools": .tools
        case "family": .heart
        case "health": .health
        case "housing": .home
        case "fees", "shopping": .creditCard
        case "salary", "extra", "interest", "refunds", "other-income": .arrowDownLeft
        default: .moreFilled
        }
    }

    public static func color(for category: TransactionCategory?) -> Color {
        KWColor.category(id: category?.id ?? TransactionCategory.otherExpenseID)
    }

    /// The name a person reads. Default categories are stored with their English name, so they
    /// translate by id; a category the person renamed or created keeps exactly what they typed.
    public static func name(of category: TransactionCategory) -> String {
        let isUntouchedDefault = TransactionCategory.defaults.contains { $0.id == category.id && $0.name == category.name }
        return isUntouchedDefault ? localizedDefaultName(for: category.id) ?? category.name : category.name
    }

    private static func localizedDefaultName(for id: String) -> String? {
        switch id {
        case "groceries": String(localized: "Groceries", bundle: #bundle)
        case "restaurants": String(localized: "Restaurants", bundle: #bundle)
        case "transport": String(localized: "Transport", bundle: #bundle)
        case "housing": String(localized: "Housing", bundle: #bundle)
        case "utilities": String(localized: "Utilities", bundle: #bundle)
        case "health": String(localized: "Health", bundle: #bundle)
        case "education": String(localized: "Education", bundle: #bundle)
        case "leisure": String(localized: "Leisure", bundle: #bundle)
        case "shopping": String(localized: "Shopping", bundle: #bundle)
        case "subscriptions": String(localized: "Subscriptions", bundle: #bundle)
        case "personal-care": String(localized: "Personal care", bundle: #bundle)
        case "family": String(localized: "Family", bundle: #bundle)
        case "travel": String(localized: "Travel", bundle: #bundle)
        case "fees": String(localized: "Fees", bundle: #bundle)
        case "tools": String(localized: "Tools", bundle: #bundle)
        case TransactionCategory.otherExpenseID: String(localized: "Other", bundle: #bundle)
        case "salary": String(localized: "Salary", bundle: #bundle)
        case "extra": String(localized: "Extra", bundle: #bundle)
        case "interest": String(localized: "Interest", bundle: #bundle)
        case "refunds": String(localized: "Refunds", bundle: #bundle)
        case TransactionCategory.otherIncomeID: String(localized: "Other income", bundle: #bundle)
        default: nil
        }
    }
}
