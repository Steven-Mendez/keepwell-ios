import AccountsDomain
import Core
import Domain
import Foundation
import Observation

/// Drives one debit card's screen: its art, the account it spends from and the edits a person
/// can make to it.
@MainActor
@Observable
public final class DebitCardViewModel {
    public enum State: Equatable {
        case loading
        case loaded(DebitCardDetail)
        case failed
        /// The card was removed from this screen; there is nothing left to show.
        case removed
    }

    public let cardID: UUID
    public private(set) var state = State.loading
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    private let getDetail: any GetDebitCardDetailUseCase
    private let setFrozen: any SetCardFrozenUseCase
    private let setColor: any SetCardColorUseCase
    private let renameAccount: any RenameAccountUseCase
    private let removeCard: any RemoveCardUseCase
    private let formatter = CurrencyFormatter()

    public init(
        cardID: UUID,
        getDetail: any GetDebitCardDetailUseCase,
        setFrozen: any SetCardFrozenUseCase,
        setColor: any SetCardColorUseCase,
        renameAccount: any RenameAccountUseCase,
        removeCard: any RemoveCardUseCase,
    ) {
        self.cardID = cardID
        self.getDetail = getDetail
        self.setFrozen = setFrozen
        self.setColor = setColor
        self.renameAccount = renameAccount
        self.removeCard = removeCard
    }

    public var detail: DebitCardDetail? {
        if case let .loaded(detail) = state {
            detail
        } else {
            nil
        }
    }

    public func load() async {
        guard state != .removed else { return }
        do {
            state = try await .loaded(getDetail.execute(cardID: cardID))
        } catch {
            state = .failed
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    // MARK: - Edits

    public func toggleFrozen() async {
        guard let detail else { return }
        _ = await perform { () async throws(DomainError) in
            try await setFrozen.execute(cardID: cardID, isFrozen: !detail.card.isFrozen)
        }
    }

    /// Returns whether the sheet can close.
    public func setColor(_ color: CardColor) async -> Bool {
        await perform { () async throws(DomainError) in
            try await setColor.execute(cardID: cardID, color: color)
        }
    }

    /// Returns whether the sheet can close.
    public func rename(to name: String) async -> Bool {
        guard let detail else { return false }
        let saved = await perform { () async throws(DomainError) in
            try await renameAccount.execute(accountID: detail.account.id, name: name)
        }
        if !saved, name.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = String(localized: "Write a name for the account.", bundle: #bundle)
        }
        return saved
    }

    /// Returns whether the card is gone, so the screen can close.
    public func remove() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await removeCard.execute(cardID: cardID)
            errorMessage = nil
            state = .removed
            return true
        } catch {
            errorMessage = Self.saveError
            return false
        }
    }

    private func perform(_ action: () async throws(DomainError) -> Void) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await action()
            errorMessage = nil
            await load()
            return true
        } catch {
            errorMessage = Self.saveError
            return false
        }
    }

    private static var saveError: String {
        String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
    }

    // MARK: - Display

    /// The bank printed on the card, falling back to the account's own name.
    func bank(_ detail: DebitCardDetail) -> String {
        detail.account.bank ?? detail.account.name
    }

    /// "Balance $9,994.55", plus how many cards share it when there are several.
    func subtitle(_ detail: DebitCardDetail) -> String {
        let balance = formatter.string(detail.balance)
        let label = String(localized: "Balance \(balance)", bundle: #bundle)
        guard detail.cardCount > 1 else { return label }
        let count = detail.cardCount
        return "\(label) · \(String(localized: "shared by \(count) cards", bundle: #bundle))"
    }
}
