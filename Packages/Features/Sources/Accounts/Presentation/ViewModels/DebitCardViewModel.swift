import AccountsDomain
import Core
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives a bank account's screen, which is also its card's: one name, one color, one freeze and
/// one delete, because the person sees the account and its card as the same thing.
@MainActor
@Observable
public final class DebitCardViewModel {
    public enum State: Equatable {
        case loading
        case loaded(DebitCardDetail)
        case failed
        /// The account was deleted from this screen; there is nothing left to show.
        case deleted
    }

    public let accountID: UUID
    public private(set) var state = State.loading
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    /// The person's own name, printed on their main cards.
    public private(set) var ownerName: String?

    private let getDetail: any GetDebitCardDetailUseCase
    private let setFrozen: any SetCardFrozenUseCase
    private let setColor: any SetCardColorUseCase
    private let renameAccount: any RenameAccountUseCase
    private let deleteAccount: any DeleteAccountUseCase
    private let getPreferredName: any GetPreferredNameUseCase
    private let formatter = CurrencyFormatter()

    public init(
        accountID: UUID,
        getDetail: any GetDebitCardDetailUseCase,
        setFrozen: any SetCardFrozenUseCase,
        setColor: any SetCardColorUseCase,
        renameAccount: any RenameAccountUseCase,
        deleteAccount: any DeleteAccountUseCase,
        getPreferredName: any GetPreferredNameUseCase,
    ) {
        self.getPreferredName = getPreferredName
        self.accountID = accountID
        self.getDetail = getDetail
        self.setFrozen = setFrozen
        self.setColor = setColor
        self.renameAccount = renameAccount
        self.deleteAccount = deleteAccount
    }

    public var detail: DebitCardDetail? {
        if case let .loaded(detail) = state {
            detail
        } else {
            nil
        }
    }

    public func load() async {
        guard state != .deleted else { return }
        ownerName = await getPreferredName.execute()
        do {
            state = try await .loaded(getDetail.execute(accountID: accountID))
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
            try await setFrozen.execute(cardID: detail.card.id, isFrozen: !detail.card.isFrozen)
        }
    }

    /// Returns whether the sheet can close.
    public func setColor(_ color: CardColor) async -> Bool {
        guard let cardID = detail?.card.id else { return false }
        return await perform { () async throws(DomainError) in
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

    /// Returns whether the account is gone, so the screen can close.
    public func delete() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await deleteAccount.execute(accountID: accountID)
            errorMessage = nil
            state = .deleted
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

    /// "$9,994.55", the account's balance the header shows big.
    func balance(_ detail: DebitCardDetail) -> String {
        formatter.string(detail.balance)
    }

    /// "Bank account · USD": the hero names what the card is, since it is also the account.
    func subtitle(_ detail: DebitCardDetail) -> String {
        let currencies = detail.account.currencies.formatted(.list(type: .and))
        return String(localized: "Bank account · \(currencies)", bundle: #bundle)
    }

    /// "Delete Bank One Savings?"
    func deleteTitle(_ detail: DebitCardDetail) -> String {
        let name = CardDisplay.name(of: detail.account)
        return String(localized: "Delete \(name)?", bundle: #bundle)
    }

    /// Says what goes with the account before the person confirms, including the part that
    /// reaches other accounts: transfers with them disappear, so their balances change too.
    func deleteMessage(_ detail: DebitCardDetail) -> String {
        let count = detail.movementCount
        guard count > 0 else {
            return String(localized: "The account and its card are deleted. This can't be undone.", bundle: #bundle)
        }
        return String(
            localized: "The account, its card and its \(count) movements are deleted, including transfers with your other accounts, so their balances change too. This can't be undone.",
            bundle: #bundle,
        )
    }

    var display: TransactionDisplay? {
        detail.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }
}
