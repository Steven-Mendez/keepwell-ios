import Core
import CreditCardDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives a credit card's detail and the edits made from it.
@MainActor
@Observable
public final class CreditCardViewModel {
    public enum State: Equatable {
        case loading
        case loaded(CreditCardDetail)
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

    private let getDetail: any GetCreditCardDetailUseCase
    private let updateTerms: any UpdateCreditTermsUseCase
    private let setCardColor: any SetCardColorUseCase
    private let setCardDetails: any SetCardDetailsUseCase
    private let setCardNumber: any SetCardNumberUseCase
    private let renameAccount: any RenameAccountUseCase
    private let deleteAccount: any DeleteAccountUseCase
    private let getPreferredName: any GetPreferredNameUseCase
    let formatter = CurrencyFormatter()

    public init(
        accountID: UUID,
        getDetail: any GetCreditCardDetailUseCase,
        updateTerms: any UpdateCreditTermsUseCase,
        setCardColor: any SetCardColorUseCase,
        setCardDetails: any SetCardDetailsUseCase,
        setCardNumber: any SetCardNumberUseCase,
        renameAccount: any RenameAccountUseCase,
        deleteAccount: any DeleteAccountUseCase,
        getPreferredName: any GetPreferredNameUseCase,
    ) {
        self.getPreferredName = getPreferredName
        self.accountID = accountID
        self.getDetail = getDetail
        self.updateTerms = updateTerms
        self.setCardColor = setCardColor
        self.setCardDetails = setCardDetails
        self.setCardNumber = setCardNumber
        self.renameAccount = renameAccount
        self.deleteAccount = deleteAccount
    }

    public var detail: CreditCardDetail? {
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

    /// Empty texts clear the value. Returns whether the sheet can close.
    public func saveTerms(limitText: String, cutoffDay: Int?, dueDay: Int?) async -> Bool {
        guard let detail else { return false }
        let trimmed = limitText.trimmingCharacters(in: .whitespaces)
        var limit: Money?
        if !trimmed.isEmpty {
            guard let amount = AmountInput.decimal(from: trimmed), amount > 0 else {
                errorMessage = String(localized: "Check the credit limit.", bundle: #bundle)
                return false
            }
            limit = Money(amount, detail.limitCurrency)
        }
        return await perform { () async throws(DomainError) in
            try await updateTerms.execute(accountID: accountID, limit: limit, cutoffDay: cutoffDay, dueDay: dueDay)
        }
    }

    /// Repaints the card's plastic. Returns whether the sheet can close.
    public func setHolderColor(_ color: CardColor) async -> Bool {
        guard let holderID = detail?.holder?.id else { return false }
        return await perform { () async throws(DomainError) in
            try await setCardColor.execute(cardID: holderID, color: color)
        }
    }

    /// Saves the plastic's product name and expiry. Returns whether the sheet can close.
    public func setHolderDetails(productName: String?, expiry: CardExpiry?) async -> Bool {
        guard let holderID = detail?.holder?.id else { return false }
        return await perform { () async throws(DomainError) in
            try await setCardDetails.execute(cardID: holderID, productName: productName, expiry: expiry)
        }
    }

    /// Saves the plastic's last four digits (required on a credit card) and network. Returns whether
    /// the sheet can close.
    public func setHolderNumber(lastFour: String, network: CardNetwork?) async -> Bool {
        guard let holderID = detail?.holder?.id else { return false }
        return await perform { () async throws(DomainError) in
            try await setCardNumber.execute(cardID: holderID, lastFour: lastFour, network: network)
        }
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

    /// Renames the card's account. Returns whether the sheet can close.
    public func rename(to name: String) async -> Bool {
        let saved = await perform { () async throws(DomainError) in
            try await renameAccount.execute(accountID: accountID, name: name)
        }
        if !saved, name.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = String(localized: "Write a name for the card.", bundle: #bundle)
        }
        return saved
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

    var display: TransactionDisplay? {
        detail.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    func money(_ money: Money, fractionDigits: Int = 2) -> String {
        formatter.string(money, fractionDigits: fractionDigits)
    }

    /// A dual card's debts with the second currency first, as the accounts list shows them.
    func debtsSecondFirst(_ detail: CreditCardDetail) -> [Money] {
        detail.balances.reversed()
    }

    /// A dual card's headline: each currency's debt side by side, second currency first, so no
    /// amounts in different currencies are ever added without the rate.
    func headline(_ detail: CreditCardDetail) -> String {
        guard detail.balances.count > 1 else { return owed(detail.totalDebt) }
        return debtsSecondFirst(detail).map(owed).joined(separator: " · ")
    }

    /// Debt reads as a positive amount owed.
    func owed(_ money: Money) -> String {
        formatter.string(Money(-money.amount, money.currency))
    }

    /// "Delete Bank One Premia?"
    func deleteTitle(_ detail: CreditCardDetail) -> String {
        let name = CardDisplay.name(of: detail.account)
        return String(localized: "Delete \(name)?", bundle: #bundle)
    }

    /// Says what goes with the account before the person confirms, including the transfers that
    /// reach other accounts, whose balances change too.
    func deleteMessage(_ detail: CreditCardDetail) -> String {
        let count = detail.movementCount
        guard count > 0 else {
            return String(localized: "The account and its card are deleted. This can't be undone.", bundle: #bundle)
        }
        return String(
            localized: "The account, its card and its \(count) movements are deleted, including transfers with your other accounts, so their balances change too. This can't be undone.",
            bundle: #bundle,
        )
    }

    /// "Total $1,234.00": the whole debt of a dual card, only when the rate allows adding it up.
    func totalDebtLine(_ detail: CreditCardDetail) -> String? {
        guard detail.showsTotalDebt else { return nil }
        let total = owed(detail.totalDebt)
        return String(localized: "Total \(total)", bundle: #bundle)
    }

    func dayOfMonth(_ day: Int?, next: Date?) -> String? {
        guard let day else { return nil }
        guard let next else { return String(localized: "Day \(day)", bundle: #bundle) }
        let date = next.formatted(.dateTime.day().month(.abbreviated))
        return String(localized: "Day \(day) · next \(date)", bundle: #bundle)
    }
}

extension CreditCardViewModel {
    func bank(_ detail: CreditCardDetail) -> String {
        detail.account.bank ?? detail.account.name
    }
}
