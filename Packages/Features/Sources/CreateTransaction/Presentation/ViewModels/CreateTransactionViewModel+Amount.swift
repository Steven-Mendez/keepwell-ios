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

    // MARK: Amount

    /// The design's keypad: one dot, at most nine characters, a lone zero is replaced, and
    /// deleting the last digit leaves "0". Cents stop at two decimals since money has no more.
    public func press(_ key: Key) {
        switch key {
        case .delete:
            amountText = amountText.count > 1 ? String(amountText.dropLast()) : "0"
        case .dot:
            if !amountText.contains("."), amountText.count < Self.maxAmountLength {
                amountText += "."
            }
        case let .digit(value):
            if let dot = amountText.firstIndex(of: "."), amountText[amountText.index(after: dot)...].count >= 2 {
                return
            }
            if amountText == "0" {
                amountText = String(value)
            } else if amountText.count < Self.maxAmountLength {
                amountText += String(value)
            }
        }
    }

    public var amount: Decimal {
        Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    public var canContinueFromAmount: Bool {
        amount > 0 && (!type.movesBetweenAccounts || canContinueFromAccounts)
    }

    public func continueFromAmount() {
        guard canContinueFromAmount else { return }
        if isEditing {
            path = []
            return
        }
        if type.movesBetweenAccounts {
            path = [.amount, .review]
            return
        }
        path = [.category]
        if let presetCategoryID, categories.contains(where: { $0.id == presetCategoryID }) {
            selectCategory(presetCategoryID, byPerson: false)
        }
    }
}
