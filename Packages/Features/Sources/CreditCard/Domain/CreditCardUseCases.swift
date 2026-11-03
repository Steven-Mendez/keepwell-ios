import Domain
import Foundation

/// "Complete card details": limit, cutoff and due day. `nil` clears a value.
public protocol UpdateCreditTermsUseCase: Sendable {
    func execute(accountID: UUID, limit: Money?, cutoffDay: Int?, dueDay: Int?) async throws(DomainError)
}

public struct DefaultUpdateCreditTermsUseCase: UpdateCreditTermsUseCase {
    private let accounts: any AccountRepository

    public init(accounts: any AccountRepository) {
        self.accounts = accounts
    }

    public func execute(accountID: UUID, limit: Money?, cutoffDay: Int?, dueDay: Int?) async throws(DomainError) {
        guard let account = try await accounts.fetchAccounts().first(where: { $0.id == accountID && $0.kind == .credit }) else {
            throw .notFound(accountID)
        }
        if let limit, limit.amount <= 0 {
            throw .invalidAmount
        }
        let terms = try CreditTerms(
            debtMode: account.creditTerms?.debtMode ?? (account.currencies.count > 1 ? .dual : .principal),
            limit: limit,
            cutoffDay: cutoffDay,
            dueDay: dueDay,
        )
        try await accounts.save(Account(
            id: account.id,
            name: account.name,
            bank: account.bank,
            kind: account.kind,
            openingBalances: account.openingBalances,
            openingDate: account.openingDate,
            creditTerms: terms,
        ))
    }
}

/// What a new additional card starts with; the holder's network is reused.
public struct NewAdditionalCard: Sendable {
    public let accountID: UUID
    public let holderName: String
    public let lastFour: String?
    public let color: CardColor
    public let cycleCap: Money?

    public init(accountID: UUID, holderName: String, lastFour: String?, color: CardColor, cycleCap: Money?) {
        self.accountID = accountID
        self.holderName = holderName
        self.lastFour = lastFour
        self.color = color
        self.cycleCap = cycleCap
    }
}

public protocol AddAdditionalCardUseCase: Sendable {
    func execute(_ new: NewAdditionalCard) async throws(DomainError) -> Card
}

public struct DefaultAddAdditionalCardUseCase: AddAdditionalCardUseCase {
    private let cards: any CardRepository

    public init(cards: any CardRepository) {
        self.cards = cards
    }

    public func execute(_ new: NewAdditionalCard) async throws(DomainError) -> Card {
        let name = new.holderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw .missingName }
        if let cap = new.cycleCap, cap.amount <= 0 {
            throw .invalidAmount
        }
        let holder = try await cards.fetchCards().first { $0.accountID == new.accountID && $0.kind == .creditHolder }
        let card = try Card(
            accountID: new.accountID,
            kind: .creditAdditional,
            network: holder?.network,
            lastFour: new.lastFour,
            color: new.color,
            additional: AdditionalCardControls(holderName: name, cycleCap: new.cycleCap),
        )
        try await cards.save(card)
        return card
    }
}

/// Saves new controls on an additional card: cap, allowed categories, alerts, freeze.
public protocol UpdateAdditionalCardUseCase: Sendable {
    func execute(cardID: UUID, controls: AdditionalCardControls) async throws(DomainError)
}

public struct DefaultUpdateAdditionalCardUseCase: UpdateAdditionalCardUseCase {
    private let cards: any CardRepository

    public init(cards: any CardRepository) {
        self.cards = cards
    }

    public func execute(cardID: UUID, controls: AdditionalCardControls) async throws(DomainError) {
        guard let card = try await cards.fetchCards().first(where: { $0.id == cardID && $0.kind == .creditAdditional }) else {
            throw .notFound(cardID)
        }
        if let cap = controls.cycleCap, cap.amount <= 0 {
            throw .invalidAmount
        }
        try await cards.save(Card(
            id: card.id,
            accountID: card.accountID,
            kind: card.kind,
            network: card.network,
            lastFour: card.lastFour,
            color: card.color,
            additional: controls,
        ))
    }
}

/// "Remove additional". Its past purchases stay on the card's account.
public protocol RemoveAdditionalCardUseCase: Sendable {
    func execute(cardID: UUID) async throws(DomainError)
}

public struct DefaultRemoveAdditionalCardUseCase: RemoveAdditionalCardUseCase {
    private let cards: any CardRepository

    public init(cards: any CardRepository) {
        self.cards = cards
    }

    public func execute(cardID: UUID) async throws(DomainError) {
        try await cards.deleteCard(id: cardID)
    }
}

extension AdditionalCardControls {
    /// A copy with some fields changed; the rest kept.
    public func with(
        cycleCap: Money?? = .none,
        allowedCategoryIDs: [String]? = nil,
        defaultCategoryID: String?? = .none,
        alertEachPurchase: Bool? = nil,
        alertNearCap: Bool? = nil,
        isFrozen: Bool? = nil,
    ) -> Self {
        Self(
            holderName: holderName,
            cycleCap: cycleCap ?? self.cycleCap,
            allowedCategoryIDs: allowedCategoryIDs ?? self.allowedCategoryIDs,
            defaultCategoryID: defaultCategoryID ?? self.defaultCategoryID,
            alertEachPurchase: alertEachPurchase ?? self.alertEachPurchase,
            alertNearCap: alertNearCap ?? self.alertNearCap,
            isFrozen: isFrozen ?? self.isFrozen,
        )
    }
}

/// Freezes or unfreezes a plastic, so it can't be chosen to pay while frozen.
public protocol SetCardFrozenUseCase: Sendable {
    func execute(cardID: UUID, isFrozen: Bool) async throws(DomainError)
}

public struct DefaultSetCardFrozenUseCase: SetCardFrozenUseCase {
    private let cards: any CardRepository

    public init(cards: any CardRepository) {
        self.cards = cards
    }

    public func execute(cardID: UUID, isFrozen: Bool) async throws(DomainError) {
        guard let card = try await cards.fetchCards().first(where: { $0.id == cardID }) else {
            throw .notFound(cardID)
        }
        try await cards.save(card.with(isFrozen: isFrozen))
    }
}
