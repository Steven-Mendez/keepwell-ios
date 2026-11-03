import Foundation

// Edits a person makes from a card's own screen. Credit and debit card screens live in different
// features, and features can't depend on each other, so the shared edits live in the kernel.

/// Repaints a plastic's art. Transfer channels have no art, so they are refused.
public protocol SetCardColorUseCase: Sendable {
    func execute(cardID: UUID, color: CardColor) async throws(DomainError)
}

public struct DefaultSetCardColorUseCase: SetCardColorUseCase {
    private let cards: any CardRepository

    public init(cards: any CardRepository) {
        self.cards = cards
    }

    public func execute(cardID: UUID, color: CardColor) async throws(DomainError) {
        guard let card = try await cards.fetchCards().first(where: { $0.id == cardID && $0.kind != .transfer }) else {
            throw .notFound(cardID)
        }
        try await cards.save(card.with(color: color))
    }
}

/// Renames an account: the nickname its cards show ("Savings", "Travel card").
public protocol RenameAccountUseCase: Sendable {
    func execute(accountID: UUID, name: String) async throws(DomainError)
}

public struct DefaultRenameAccountUseCase: RenameAccountUseCase {
    private let accounts: any AccountRepository

    public init(accounts: any AccountRepository) {
        self.accounts = accounts
    }

    public func execute(accountID: UUID, name: String) async throws(DomainError) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .missingName }
        guard let account = try await accounts.fetchAccounts().first(where: { $0.id == accountID }) else {
            throw .notFound(accountID)
        }
        try await accounts.save(account.with(name: trimmed))
    }
}

extension Card {
    /// The same card with new art.
    public func with(color: CardColor) -> Self {
        guard let copy = try? Self(
            id: id,
            accountID: accountID,
            kind: kind,
            network: network,
            lastFour: lastFour,
            color: color,
        ) else { return self }
        return copy
    }
}

extension Account {
    public func with(name: String) -> Self {
        Self(
            id: id,
            name: name,
            bank: bank,
            kind: kind,
            openingBalances: openingBalances,
            openingDate: openingDate,
            creditTerms: creditTerms,
        )
    }
}
