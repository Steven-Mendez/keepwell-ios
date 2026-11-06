import Core
import DesignSystem
import Domain
import Foundation

/// How one movement reads in a list row: style, subtitle and the two amounts. Shared by home, the
/// movement list and a card's cycle so the same movement never reads differently across screens.
public struct TransactionDisplay: Sendable {
    private let accounts: [UUID: Account]
    private let cards: [UUID: Card]
    private let categories: [String: TransactionCategory]
    private let formatter = CurrencyFormatter()

    public init(accounts: [Account], cards: [Card], categories: [TransactionCategory]) {
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.cards = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.categories = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func style(of transaction: Transaction) -> KWTransactionStyle {
        guard transaction.isConfirmed else { return .planned }
        return switch transaction.kind {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
    }

    public func category(of transaction: Transaction) -> TransactionCategory? {
        transaction.categoryID.flatMap { categories[$0] }
    }

    public func categoryName(of transaction: Transaction) -> String? {
        category(of: transaction).map(CategoryDisplay.name(of:))
    }

    /// "Debit •••• 3922", or the account's name when no card was used ("Cash").
    public func methodName(of transaction: Transaction) -> String {
        let account = accounts[transaction.accountID]
        if let card = transaction.cardID.flatMap({ cards[$0] }) {
            return CardDisplay.methodTitle(card, account: account)
        }
        return account.map(CardDisplay.name(of:)) ?? ""
    }

    public func accountName(_ id: UUID?) -> String {
        id.flatMap { accounts[$0] }.map(CardDisplay.name(of:)) ?? ""
    }

    /// "Groceries · Debit •••• 3922"; transfers read "Savings → Cash".
    public func subtitle(of transaction: Transaction) -> String {
        if transaction.kind == .transfer {
            return "\(accountName(transaction.accountID)) → \(accountName(transaction.destinationAccountID))"
        }
        return [categoryName(of: transaction), methodName(of: transaction)]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Signed by direction: "−C$250.00", "+$3.02"; transfers carry no sign since they aren't spending.
    public func amount(of transaction: Transaction) -> String {
        let sign: CurrencyFormatter.Sign = transaction.kind == .transfer ? .never : .always
        let signed = transaction.kind == .expense ? -transaction.amount : transaction.amount
        return formatter.string(from: signed, currencyCode: transaction.currency, sign: sign)
    }

    /// The amount in the other currency: what the bank debited when it reported it, an estimate
    /// ("≈") for planned movements, or the conversion at the stored rate.
    public func secondaryAmount(of transaction: Transaction) -> String? {
        let rate = transaction.exchangeRate
        guard rate.hasSecondCurrency else { return nil }
        let other = transaction.currency == rate.principal ? rate.second : rate.principal
        if let debited = transaction.actualDebitedPrincipal {
            let amount = formatter.string(from: debited, currencyCode: rate.principal)
            return String(localized: "\(amount) debited", bundle: #bundle)
        }
        let converted = formatter.string(from: transaction.amount(in: other), currencyCode: other)
        return transaction.isConfirmed ? converted : "≈ \(converted)"
    }

    /// Lowercased text a search matches against: description, note, category and method.
    public func searchableText(of transaction: Transaction) -> String {
        [
            transaction.description,
            transaction.note,
            categoryName(of: transaction),
            category(of: transaction)?.name,
            subtitle(of: transaction),
        ]
        .compactMap(\.self)
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
