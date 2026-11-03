import Foundation

// A bank account is one card: the person thinks of "my Savings" and "my Visa debit" as the same
// thing, so every deposit account carries exactly one debit card (plus the transfer channel for
// money that leaves without a card). These rules keep that true for new and existing data.

extension Card {
    /// The debit card a new bank account is created with. Without `lastFour` it still exists, so
    /// the account has a face on Accounts and something to pick when paying.
    public static func debit(
        for accountID: UUID,
        lastFour: String? = nil,
        network: CardNetwork? = nil,
        color: CardColor = .coral,
    ) throws(DomainError) -> Self {
        let digits = lastFour?.trimmingCharacters(in: .whitespaces)
        return try Self(
            accountID: accountID,
            kind: .debit,
            network: network,
            lastFour: digits?.isEmpty == false ? digits : nil,
            color: color,
        )
    }
}

extension Transaction {
    /// The same movement paid with another method of the same account.
    public func with(cardID: UUID?) -> Self {
        Self(
            id: id, date: date, status: status, description: description, kind: kind, categoryID: categoryID,
            amount: amount, currency: currency, accountID: accountID, cardID: cardID,
            destinationAccountID: destinationAccountID, actualDebitedPrincipal: actualDebitedPrincipal,
            exchangeRate: exchangeRate, isShared: isShared, note: note,
        )
    }
}

/// Brings data from before "one account, one card" (or two devices that each filled a gap before
/// syncing) to the rule: every bank account ends with exactly one debit card and one transfer
/// channel. Duplicates are merged into the most used one and their movements move with them;
/// nothing is ever deleted except the emptied duplicate methods. Safe to run on every launch.
public protocol NormalizeBankCardsUseCase: Sendable {
    /// Returns whether anything changed.
    @discardableResult
    func execute() async throws(DomainError) -> Bool
}

public struct DefaultNormalizeBankCardsUseCase: NormalizeBankCardsUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository

    public init(accounts: any AccountRepository, cards: any CardRepository, transactions: any TransactionRepository) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
    }

    @discardableResult
    public func execute() async throws(DomainError) -> Bool {
        let deposits = try await accounts.fetchAccounts().filter { $0.kind == .deposit }
        guard !deposits.isEmpty else { return false }
        let allCards = try await cards.fetchCards()
        var movements = try await transactions.fetchTransactions(in: nil)
        var changed = false
        for account in deposits {
            for kind in [CardKind.debit, .transfer] {
                let methods = allCards.filter { $0.accountID == account.id && $0.kind == kind }
                guard methods.count != 1 else { continue }
                changed = true
                guard let keeper = Self.keeper(of: methods, movements: movements) else {
                    try await cards.save(kind == .debit ? Card.debit(for: account.id) : Card(accountID: account.id, kind: .transfer))
                    continue
                }
                let merged = Set(methods.map(\.id)).subtracting([keeper.id])
                for (index, movement) in movements.enumerated() where movement.cardID.map(merged.contains) == true {
                    let moved = movement.with(cardID: keeper.id)
                    try await transactions.save(moved)
                    movements[index] = moved
                }
                for id in merged {
                    try await cards.deleteCard(id: id)
                }
            }
        }
        return changed
    }

    /// The method with the most movements; on a tie the oldest, so every device picks the same one.
    static func keeper(of methods: [Card], movements: [Transaction]) -> Card? {
        let usage = Dictionary(grouping: movements.compactMap(\.cardID)) { $0 }.mapValues(\.count)
        return methods.enumerated().max { lhs, rhs in
            let (left, right) = (usage[lhs.element.id] ?? 0, usage[rhs.element.id] ?? 0)
            return left == right ? lhs.offset > rhs.offset : left < right
        }?.element
    }
}

/// "Delete account": the account, its cards and every movement that touches it. Transfers to and
/// from other accounts go too, because a movement can't point at an account that no longer exists;
/// the screen says so before asking.
public protocol DeleteAccountUseCase: Sendable {
    func execute(accountID: UUID) async throws(DomainError)
}

public struct DefaultDeleteAccountUseCase: DeleteAccountUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository

    public init(accounts: any AccountRepository, cards: any CardRepository, transactions: any TransactionRepository) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
    }

    public func execute(accountID: UUID) async throws(DomainError) {
        guard try await accounts.fetchAccounts().contains(where: { $0.id == accountID }) else {
            throw .notFound(accountID)
        }
        let scope = TransactionScope.account(accountID)
        for movement in try await transactions.fetchTransactions(in: nil) where scope.includes(movement) {
            try await transactions.deleteTransaction(id: movement.id)
        }
        for card in try await cards.fetchCards() where card.accountID == accountID {
            try await cards.deleteCard(id: card.id)
        }
        try await accounts.deleteAccount(id: accountID)
    }
}
