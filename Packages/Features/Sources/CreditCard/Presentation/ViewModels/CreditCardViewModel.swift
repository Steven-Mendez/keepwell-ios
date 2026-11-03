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
    }

    public let accountID: UUID
    public private(set) var state = State.loading
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    /// The person's own name, printed on their main cards.
    public private(set) var ownerName: String?

    private let getDetail: any GetCreditCardDetailUseCase
    private let updateTerms: any UpdateCreditTermsUseCase
    private let setCardFrozen: any SetCardFrozenUseCase
    private let setCardColor: any SetCardColorUseCase
    private let renameAccount: any RenameAccountUseCase
    private let getPreferredName: any GetPreferredNameUseCase
    let formatter = CurrencyFormatter()

    public init(
        accountID: UUID,
        getDetail: any GetCreditCardDetailUseCase,
        updateTerms: any UpdateCreditTermsUseCase,
        setCardFrozen: any SetCardFrozenUseCase,
        setCardColor: any SetCardColorUseCase,
        renameAccount: any RenameAccountUseCase,
        getPreferredName: any GetPreferredNameUseCase,
    ) {
        self.getPreferredName = getPreferredName
        self.accountID = accountID
        self.getDetail = getDetail
        self.updateTerms = updateTerms
        self.setCardFrozen = setCardFrozen
        self.setCardColor = setCardColor
        self.renameAccount = renameAccount
    }

    public var detail: CreditCardDetail? {
        if case let .loaded(detail) = state {
            detail
        } else {
            nil
        }
    }

    public func load() async {
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

    public func setHolderFrozen(_ isFrozen: Bool) async {
        guard let holderID = detail?.holder?.id else { return }
        _ = await perform { () async throws(DomainError) in
            try await setCardFrozen.execute(cardID: holderID, isFrozen: isFrozen)
        }
    }

    /// Repaints the card's plastic. Returns whether the sheet can close.
    public func setHolderColor(_ color: CardColor) async -> Bool {
        guard let holderID = detail?.holder?.id else { return false }
        return await perform { () async throws(DomainError) in
            try await setCardColor.execute(cardID: holderID, color: color)
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

    /// Debt reads as a positive amount owed.
    func owed(_ money: Money) -> String {
        formatter.string(Money(-money.amount, money.currency))
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
