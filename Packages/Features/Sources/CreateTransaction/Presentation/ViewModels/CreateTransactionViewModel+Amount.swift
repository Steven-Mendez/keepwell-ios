import Core
import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// How the amount reads while it's typed, and the description stored when none is given.
extension CreateTransactionViewModel {
    public var currencyOptions: [String] {
        guard let currencies = context?.currencies else { return [currency] }
        return [currencies.second, currencies.principal].compactMap(\.self)
    }

    /// "−C$879" as typed, with the sign of the movement.
    public var amountDisplay: String {
        sign + CurrencyFormatter.symbol(for: currency) + amountText
    }

    public var sign: String {
        switch kind {
        case .expense: "−"
        case .income: "+"
        case .transfer: ""
        }
    }

    /// What gets stored when the person leaves the description empty. Resolved here, not in the use
    /// case, so the persisted text is in the language they were using at creation time.
    var descriptionPlaceholder: String {
        switch type {
        case .expense, .income:
            category.map(CategoryDisplay.name(of:)) ?? String(localized: "transfer.noun", defaultValue: "Transfer", bundle: #bundle)
        case .transfer: String(localized: "transfer.noun", defaultValue: "Transfer", bundle: #bundle)
        case .withdrawal: String(localized: "ATM withdrawal", bundle: #bundle)
        case .cardPayment: String(localized: "Card payment", bundle: #bundle)
        }
    }
}
