import Core
import CreditCardDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives a credit card's detail and the controls of its additional cards, which share data.
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
    private let addAdditional: any AddAdditionalCardUseCase
    private let updateAdditional: any UpdateAdditionalCardUseCase
    private let removeAdditional: any RemoveAdditionalCardUseCase
    private let setCardFrozen: any SetCardFrozenUseCase
    private let setCardColor: any SetCardColorUseCase
    private let renameAccount: any RenameAccountUseCase
    private let getPreferredName: any GetPreferredNameUseCase
    let formatter = CurrencyFormatter()

    public init(
        accountID: UUID,
        getDetail: any GetCreditCardDetailUseCase,
        updateTerms: any UpdateCreditTermsUseCase,
        addAdditional: any AddAdditionalCardUseCase,
        updateAdditional: any UpdateAdditionalCardUseCase,
        removeAdditional: any RemoveAdditionalCardUseCase,
        setCardFrozen: any SetCardFrozenUseCase,
        setCardColor: any SetCardColorUseCase,
        renameAccount: any RenameAccountUseCase,
        getPreferredName: any GetPreferredNameUseCase,
    ) {
        self.getPreferredName = getPreferredName
        self.accountID = accountID
        self.getDetail = getDetail
        self.updateTerms = updateTerms
        self.addAdditional = addAdditional
        self.updateAdditional = updateAdditional
        self.removeAdditional = removeAdditional
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

    // MARK: - Holder

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

    /// Repaints the holder plastic. Returns whether the sheet can close.
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

    /// Returns the new card's id so the caller can open it.
    public func createAdditional(holderName: String, lastFour: String, color: CardColor, capText: String) async -> UUID? {
        guard let detail else { return nil }
        let digits = lastFour.trimmingCharacters(in: .whitespaces)
        if !digits.isEmpty, digits.count != 4 || !digits.allSatisfy(\.isNumber) {
            errorMessage = String(localized: "The last 4 digits must be 4 numbers.", bundle: #bundle)
            return nil
        }
        guard let cap = parsedCap(capText, currency: detail.capCurrency) else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let card = try await addAdditional.execute(NewAdditionalCard(
                accountID: accountID,
                holderName: holderName,
                lastFour: digits.isEmpty ? nil : digits,
                color: color,
                cycleCap: cap,
            ))
            errorMessage = nil
            await load()
            return card.id
        } catch {
            errorMessage = error == .missingName
                ? String(localized: "Write who carries the card.", bundle: #bundle)
                : Self.saveError
            return nil
        }
    }

    // MARK: - Additional cards

    public func setFrozen(_ cardID: UUID, _ isFrozen: Bool) async {
        await change(cardID) { $0.with(isFrozen: isFrozen) }
    }

    public func setAlertEachPurchase(_ cardID: UUID, _ isOn: Bool) async {
        await change(cardID) { $0.with(alertEachPurchase: isOn) }
    }

    public func setAlertNearCap(_ cardID: UUID, _ isOn: Bool) async {
        await change(cardID) { $0.with(alertNearCap: isOn) }
    }

    public func setDefaultCategory(_ cardID: UUID, _ categoryID: String?) async {
        await change(cardID) { $0.with(defaultCategoryID: .some(categoryID)) }
    }

    /// Empty clears the cap. Returns whether the sheet can close.
    public func setCap(_ cardID: UUID, capText: String) async -> Bool {
        guard let detail, let cap = parsedCap(capText, currency: detail.capCurrency) else { return false }
        return await change(cardID) { $0.with(cycleCap: .some(cap)) }
    }

    /// An empty list means every category, so turning all of them on stores the empty list and
    /// categories added later are allowed too; turning the last one off is refused.
    public func toggleCategory(_ cardID: UUID, _ categoryID: String) async {
        guard let detail, let controls = detail.additional(id: cardID)?.card.additional else { return }
        let all = expenseCategories.map(\.id)
        var allowed = Set(controls.allowedCategoryIDs.isEmpty ? all : controls.allowedCategoryIDs)
        if allowed.contains(categoryID) {
            guard allowed.count > 1 else { return }
            allowed.remove(categoryID)
        } else {
            allowed.insert(categoryID)
        }
        let stored = allowed.isSuperset(of: all) ? [] : all.filter(allowed.contains)
        await change(cardID) { $0.with(allowedCategoryIDs: stored) }
    }

    public func remove(_ cardID: UUID) async -> Bool {
        await perform { () async throws(DomainError) in try await removeAdditional.execute(cardID: cardID) }
    }

    @discardableResult
    private func change(_ cardID: UUID, _ transform: (AdditionalCardControls) -> AdditionalCardControls) async -> Bool {
        guard let controls = detail?.additional(id: cardID)?.card.additional else { return false }
        let updated = transform(controls)
        return await perform { () async throws(DomainError) in
            try await updateAdditional.execute(cardID: cardID, controls: updated)
        }
    }

    private func parsedCap(_ text: String, currency: String) -> Money?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .some(nil)
        }
        guard let amount = AmountInput.decimal(from: trimmed), amount > 0 else {
            errorMessage = String(localized: "Check the cap amount.", bundle: #bundle)
            return nil
        }
        return .some(Money(amount, currency))
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

    var expenseCategories: [TransactionCategory] {
        detail?.categories.filter { $0.kind == .expense } ?? []
    }

    /// "Mastercard ··6158", falling back to the bank and name.
    func title(_ detail: CreditCardDetail) -> String {
        detail.holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: detail.account)
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

    /// "Holder ··6158".
    func holderTitle(_ detail: CreditCardDetail) -> String {
        let holder = String(localized: "Holder", bundle: #bundle)
        guard let lastFour = detail.holder?.lastFour else { return holder }
        return "\(holder) ··\(lastFour)"
    }

    /// "Additional ··1234 · only Groceries" or "· every category".
    func additionalSubtitle(_ card: Card, categories: [TransactionCategory]) -> String {
        let additional = String(localized: "Additional", bundle: #bundle)
        let name = card.lastFour.map { "\(additional) ··\($0)" } ?? additional
        guard let controls = card.additional else { return name }
        if controls.isFrozen {
            return "\(name) · \(String(localized: "frozen", bundle: #bundle))"
        }
        if controls.allowedCategoryIDs.isEmpty {
            return "\(name) · \(String(localized: "every category", bundle: #bundle))"
        }
        let names = controls.allowedCategoryIDs.compactMap { id in categories.first { $0.id == id } }.map(CategoryDisplay.name(of:))
        let list = names.formatted(.list(type: .and))
        return "\(name) · \(String(localized: "only \(list)", bundle: #bundle))"
    }

    func usageCaption(_ usage: AdditionalCardUsage) -> String {
        guard let remaining = usage.remaining else {
            return String(localized: "No cap", bundle: #bundle)
        }
        let left = money(remaining, fractionDigits: 0)
        return String(localized: "\(left) left until the next cutoff", bundle: #bundle)
    }

    func isAllowed(_ categoryID: String, controls: AdditionalCardControls) -> Bool {
        controls.allowedCategoryIDs.isEmpty || controls.allowedCategoryIDs.contains(categoryID)
    }

    func thresholdPercent(_ detail: CreditCardDetail) -> String {
        "\(formatter.number(detail.capAlertThreshold * 100, fractionDigits: 0))%"
    }
}

extension CreditCardViewModel {
    func bank(_ detail: CreditCardDetail) -> String {
        detail.account.bank ?? detail.account.name
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
