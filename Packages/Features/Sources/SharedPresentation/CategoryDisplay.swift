import DesignSystem
import Domain
import Foundation
import SwiftUI

/// Name, icon and color of a category. Icons are SF Symbols: defaults map theirs by id, and a
/// category the person created keeps the one they picked. Colors come from the `category` tokens,
/// or the palette color the person picked, falling back to `faint`.
public enum CategoryDisplay {
    /// Shown when a category has no symbol of its own, and for unknown ids from an import.
    public static let fallbackSymbol = "square.grid.2x2"

    public static func symbol(for category: TransactionCategory?) -> String {
        guard let category else { return fallbackSymbol }
        return category.icon ?? defaultSymbol(for: category.id) ?? fallbackSymbol
    }

    static func defaultSymbol(for id: String) -> String? {
        switch id {
        case "groceries": "cart"
        case "restaurants": "fork.knife"
        case "transport": "bus"
        case "housing": "house"
        case "utilities": "bolt"
        case "health": "cross.case"
        case "education": "graduationcap"
        case "leisure": "theatermasks"
        case "shopping": "bag"
        case "subscriptions": "arrow.triangle.2.circlepath"
        case "personal-care": "scissors"
        case "family": "figure.2.and.child.holdinghands"
        case "travel": "airplane"
        case "fees": "building.columns"
        case "tools": "wrench.and.screwdriver"
        case "pets": "pawprint"
        case "gifts": "gift"
        case "insurance": "umbrella"
        case "taxes": "doc.text"
        case "savings": "banknote"
        case "donations": "heart.circle"
        case TransactionCategory.loanPaymentsID: "calendar.badge.clock"
        case TransactionCategory.otherExpenseID: fallbackSymbol
        case "salary": "briefcase"
        case "freelance": "laptopcomputer"
        case "extra": "star"
        case "interest": "percent"
        case "investments": "chart.line.uptrend.xyaxis"
        case "rental": "key"
        case "gifts-received": "giftcard"
        case "refunds": "arrow.uturn.backward"
        case TransactionCategory.otherIncomeID: "tray.and.arrow.down"
        default: nil
        }
    }

    /// The icons offered when creating a category, grouped loosely by what people track.
    public static let symbolChoices: [String] = [
        "cart", "basket", "fork.knife", "cup.and.saucer", "wineglass", "birthday.cake",
        "bus", "car", "fuelpump", "tram", "bicycle", "parkingsign",
        "house", "sofa", "bolt", "drop", "wifi", "phone",
        "cross.case", "pills", "heart", "dumbbell", "figure.run", "scissors",
        "bag", "tshirt", "gift", "tag", "sparkles", "cart.badge.plus",
        "graduationcap", "book", "theatermasks", "film", "music.note", "gamecontroller",
        "airplane", "suitcase", "beach.umbrella", "globe", "tent", "map",
        "pawprint", "leaf", "figure.2.and.child.holdinghands", "stroller", "umbrella", "heart.circle",
        "briefcase", "laptopcomputer", "wrench.and.screwdriver", "hammer", "paintbrush", "camera",
        "banknote", "creditcard", "building.columns", "chart.line.uptrend.xyaxis", "percent", "doc.text",
        "key", "star", "arrow.uturn.backward", "tray.and.arrow.down", "bell", "square.grid.2x2",
    ]

    /// Keys of `KWColor.categoryPalette`, in the order the editor shows them.
    public static var colorChoices: [String] {
        KWColor.categoryPalette.map(\.key)
    }

    /// Read by VoiceOver on the color choices.
    public static func colorName(_ key: String) -> String {
        switch key {
        case "blue": String(localized: "Blue", bundle: #bundle)
        case "purple": String(localized: "Purple", bundle: #bundle)
        case "pink": String(localized: "Pink", bundle: #bundle)
        case "orange": String(localized: "Orange", bundle: #bundle)
        case "amber": String(localized: "Amber", bundle: #bundle)
        case "yellow": String(localized: "Yellow", bundle: #bundle)
        case "lime": String(localized: "Lime", bundle: #bundle)
        case "green": String(localized: "Green", bundle: #bundle)
        case "cyan": String(localized: "Cyan", bundle: #bundle)
        default: String(localized: "Gray", bundle: #bundle)
        }
    }

    public static func color(for category: TransactionCategory?) -> Color {
        if let key = category?.color, let picked = KWColor.categoryPalette(key: key) {
            return picked
        }
        return KWColor.category(id: category?.id ?? TransactionCategory.otherExpenseID)
    }

    /// The name a person reads. Default categories are stored with their English name, so they
    /// translate by id; a category the person renamed or created keeps exactly what they typed.
    public static func name(of category: TransactionCategory) -> String {
        category.translatesByID ? localizedDefaultName(for: category.id) ?? category.name : category.name
    }

    /// "Other" (or "Other income") as shipped, for when the stored one isn't at hand.
    public static func shippedFallbackName(for kind: TransactionKind) -> String {
        localizedDefaultName(for: TransactionCategory.otherID(for: kind)) ?? ""
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
        case "pets": String(localized: "Pets", bundle: #bundle)
        case "gifts": String(localized: "Gifts", bundle: #bundle)
        case "insurance": String(localized: "Insurance", bundle: #bundle)
        case "taxes": String(localized: "Taxes", bundle: #bundle)
        case "savings": String(localized: "Savings", bundle: #bundle)
        case "donations": String(localized: "Donations", bundle: #bundle)
        case TransactionCategory.loanPaymentsID: String(localized: "Loan payments", bundle: #bundle)
        case TransactionCategory.otherExpenseID: String(localized: "Other", bundle: #bundle)
        case "salary": String(localized: "Salary", bundle: #bundle)
        case "freelance": String(localized: "Freelance", bundle: #bundle)
        case "extra": String(localized: "Extra", bundle: #bundle)
        case "interest": String(localized: "Interest", bundle: #bundle)
        case "investments": String(localized: "Investments", bundle: #bundle)
        case "rental": String(localized: "Rental", bundle: #bundle)
        case "gifts-received": String(localized: "Gifts received", bundle: #bundle)
        case "refunds": String(localized: "Refunds", bundle: #bundle)
        case TransactionCategory.otherIncomeID: String(localized: "Other income", bundle: #bundle)
        default: nil
        }
    }
}

/// A category's SF Symbol at the size and stroke weight of the design's line icons.
public struct CategorySymbol: View {
    private let name: String
    private let size: CGFloat

    public init(_ category: TransactionCategory?, size: CGFloat = 20) {
        name = CategoryDisplay.symbol(for: category)
        self.size = size
    }

    public init(symbol: String, size: CGFloat = 20) {
        name = symbol
        self.size = size
    }

    public var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.8, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A category's symbol on a disc of its own color, as on the web's `CategoryBadge`.
public struct CategoryBadge: View {
    private let category: TransactionCategory?
    private let size: CGFloat

    public init(_ category: TransactionCategory?, size: CGFloat = 24) {
        self.category = category
        self.size = size
    }

    public var body: some View {
        let color = CategoryDisplay.color(for: category)
        CategorySymbol(category, size: size * 0.55)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: Circle())
    }
}
