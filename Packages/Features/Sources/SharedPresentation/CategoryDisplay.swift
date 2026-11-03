import DesignSystem
import Domain
import SwiftUI

/// Icon and color of a category. Icons follow the category grid in the create-movement flow;
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
        KWColor.category(named: category?.name ?? "Otros")
    }
}
