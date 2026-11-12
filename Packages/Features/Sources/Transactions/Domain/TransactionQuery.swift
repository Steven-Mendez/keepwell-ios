import Domain
import Foundation

/// Everything that narrows the movement list at once: the kind chip, the account, and the search
/// text.
public struct TransactionQuery: Hashable, Sendable {
    public var kind: TransactionFilter
    public var scope: TransactionScope
    public var text: String

    public init(kind: TransactionFilter = .all, scope: TransactionScope = .all, text: String = "") {
        self.kind = kind
        self.scope = scope
        self.text = text
    }

    /// The text as searches compare it: trimmed, without case or accents, so "cafe" finds "Café".
    public var needle: String {
        Self.normalized(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// "#boda" in the search narrows the list to movements with that tag, rather than to the text.
    public var tag: String? {
        Tags.searched(in: text)
    }
}

/// What the movements a tag search leaves came to over all time, in the principal currency like
/// the month's totals: what was spent and what was received. Drafts and transfers don't count.
public struct TagTotals: Hashable, Sendable {
    public let tag: String
    public let currency: String
    public let expense: Decimal
    public let income: Decimal

    public init(tag: String, transactions: [Transaction], currency: String) {
        self.tag = tag
        self.currency = currency
        let counted = transactions.filter { $0.isConfirmed && $0.tags.contains(tag) }
        expense = counted.filter { $0.kind == .expense }.reduce(0) { $0 + $1.principalAmount }
        income = counted.filter { $0.kind == .income }.reduce(0) { $0 + $1.principalAmount }
    }
}

/// Narrows movements by a query. What a movement is searched by (its category's translated name,
/// the card's title) is presentation, so the caller hands it over as `searchableText`.
public protocol FilterTransactionsUseCase: Sendable {
    func execute(
        _ transactions: [Transaction],
        matching query: TransactionQuery,
        searchableText: (Transaction) -> String,
    ) -> [Transaction]
}

public struct DefaultFilterTransactionsUseCase: FilterTransactionsUseCase {
    public init() {}

    public func execute(
        _ transactions: [Transaction],
        matching query: TransactionQuery,
        searchableText: (Transaction) -> String,
    ) -> [Transaction] {
        let needle = query.needle
        let tag = query.tag
        return transactions.filter { transaction in
            let matchesText = if let tag {
                transaction.tags.contains(tag)
            } else {
                needle.isEmpty || TransactionQuery.normalized(searchableText(transaction)).contains(needle)
            }
            return query.kind.matches(transaction) && query.scope.includes(transaction) && matchesText
        }
    }
}

/// One account in the list's account picker, shown as its card: a bank account's debit card, a
/// credit card's main plastic. Cash has none and shows as cash.
public struct TransactionScopeOption: Identifiable, Hashable, Sendable {
    public let account: Account
    public let card: Card?
    public var id: UUID { account.id }

    public init(account: Account, card: Card?) {
        self.account = account
        self.card = card
    }
}

extension TransactionList {
    /// Accounts in the order the Accounts tab shows them: credit cards, bank accounts, cash. One
    /// row each. Closed accounts come last, so their history can still be looked up.
    public var scopeOptions: [TransactionScopeOption] {
        let order: [AccountKind] = [.credit, .deposit, .cash]
        return [true, false].flatMap { open in order.flatMap { kind in
            accounts.filter { $0.kind == kind && $0.isOpen == open }.map { account in
                let face: CardKind? = switch kind {
                case .deposit: .debit
                case .credit: .creditHolder
                case .cash: nil
                }
                return TransactionScopeOption(account: account, card: cards.first { $0.accountID == account.id && $0.kind == face })
            }
        } }
    }

    public func account(in scope: TransactionScope) -> Account? {
        switch scope {
        case .all: nil
        case let .account(id): accounts.first { $0.id == id }
        }
    }

    /// The balance behind a scope, one per currency the account holds, never summed across
    /// currencies. `nil` for everything, which has no single balance.
    public func balances(in scope: TransactionScope, calendar: Calendar) -> [Money]? {
        account(in: scope).map { Balances.balance(of: $0, transactions: transactions, calendar: calendar) }
    }

    /// The same balance as one amount in the principal currency, converted the way net worth is,
    /// for the headline; the per-currency balances stay available for the detail under it.
    public func balanceTotal(in scope: TransactionScope, calendar: Calendar) -> Money? {
        balances(in: scope, calendar: calendar).flatMap { try? NetWorth.total(of: $0, settings: settings) }
    }
}
