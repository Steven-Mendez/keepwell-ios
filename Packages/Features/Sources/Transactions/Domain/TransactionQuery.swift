import Domain
import Foundation

/// Everything that narrows the movement list at once: the kind chip, the account or card, and
/// the search text.
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
        return transactions.filter { transaction in
            query.kind.matches(transaction)
                && query.scope.includes(transaction)
                && (needle.isEmpty || TransactionQuery.normalized(searchableText(transaction)).contains(needle))
        }
    }
}

/// One account in the list's account picker, with the plastics that can narrow it further.
public struct TransactionScopeGroup: Identifiable, Hashable, Sendable {
    public let account: Account
    /// Holder first, then additionals; debit cards in the order they were added. Transfer
    /// channels are left out: the account itself already covers what moved through them.
    public let cards: [Card]
    public var id: UUID { account.id }

    public init(account: Account, cards: [Card]) {
        self.account = account
        self.cards = cards
    }
}

extension TransactionList {
    /// Accounts in the order the Accounts tab shows them: credit cards, bank accounts, cash.
    public var scopeGroups: [TransactionScopeGroup] {
        let order: [AccountKind] = [.credit, .deposit, .cash]
        return order.flatMap { kind in
            accounts.filter { $0.kind == kind }.map { account in
                let plastics = cards.filter { $0.accountID == account.id && $0.kind != .transfer }
                let ordered = plastics.filter { $0.kind == .creditHolder } + plastics.filter { $0.kind != .creditHolder }
                return TransactionScopeGroup(account: account, cards: ordered)
            }
        }
    }

    public func card(in scope: TransactionScope) -> Card? {
        guard case let .card(id) = scope else { return nil }
        return cards.first { $0.id == id }
    }

    /// The account a scope looks at; a card's is the account it draws from.
    public func account(in scope: TransactionScope) -> Account? {
        switch scope {
        case .all: nil
        case let .account(id): accounts.first { $0.id == id }
        case .card: card(in: scope).flatMap { card in accounts.first { $0.id == card.accountID } }
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
