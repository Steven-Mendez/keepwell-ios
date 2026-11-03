import AddCardDomain
import Core
import Domain
import Foundation
import Observation

/// Drives "Add card": type → plastic → debt and cycle (credit only) → added.
@MainActor
@Observable
public final class AddCardViewModel {
    public enum Kind: Sendable {
        case credit
        case debit
    }

    public enum Step: Hashable, Sendable {
        case plastic
        case debt
        case done
    }

    public enum Exit: Sendable {
        case close
        case viewCreditCard(UUID)
        case addAdditional(UUID)
    }

    public var path: [Step] = []
    public private(set) var kind = Kind.credit
    public var bank = ""
    public var lastFour = ""
    public var network = CardNetwork.mastercard
    public var color = CardColor.azul
    public var debtMode = DebtMode.dual
    public var principalDebtText = "0.00"
    public var secondDebtText = "0.00"
    public var limitText = ""
    public private(set) var cutoffDay = 28
    public private(set) var dueDay = 15
    public var linkedAccountID: UUID?
    public private(set) var context: AddCardContext?
    public private(set) var createdAccount: Account?
    public private(set) var createdCard: Card?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let getContext: any GetAddCardContextUseCase
    private let addCredit: any AddCreditCardUseCase
    private let addDebit: any AddDebitCardUseCase
    private let addAccount: any AddAccountUseCase

    public init(
        getContext: any GetAddCardContextUseCase,
        addCredit: any AddCreditCardUseCase,
        addDebit: any AddDebitCardUseCase,
        addAccount: any AddAccountUseCase,
    ) {
        self.getContext = getContext
        self.addCredit = addCredit
        self.addDebit = addDebit
        self.addAccount = addAccount
    }

    public func load() async {
        context = try? await getContext.execute()
        if context?.currencies.second == nil {
            debtMode = .principal
        }
    }

    public var principal: String {
        context?.currencies.principal ?? "USD"
    }

    public var second: String? {
        context?.currencies.second
    }

    // MARK: Steps

    /// Starts the plastic step; `accountID` preselects the bank account when linking a debit card
    /// from an account's "Link another card".
    public func choose(_ kind: Kind, linkingTo accountID: UUID? = nil) {
        self.kind = kind
        network = kind == .credit ? .mastercard : .visa
        color = kind == .credit ? .azul : .coral
        linkedAccountID = accountID ?? linkedAccountID ?? context?.depositAccounts.first?.id
        errorMessage = nil
        path = [.plastic]
    }

    public var isLastFourValid: Bool {
        lastFour.count == 4 && lastFour.allSatisfy(\.isNumber)
    }

    public var canContinueFromPlastic: Bool {
        isLastFourValid && (kind == .credit || linkedAccountID != nil)
    }

    /// Credit cards go on to debt and cycle; debit cards are saved right away.
    public func continueFromPlastic() async {
        guard canContinueFromPlastic else { return }
        switch kind {
        case .credit: path.append(.debt)
        case .debit: await saveDebit()
        }
    }

    public func stepCutoff(by delta: Int) {
        cutoffDay = Self.wrapDay(cutoffDay + delta)
    }

    public func stepDue(by delta: Int) {
        dueDay = Self.wrapDay(dueDay + delta)
    }

    public var canAddCreditCard: Bool {
        Self.amount(principalDebtText) != nil && Self.amount(secondDebtText) != nil
            && (limitText.trimmingCharacters(in: .whitespaces).isEmpty || AmountInput.decimal(from: limitText).map { $0 > 0 } == true)
    }

    public func addCreditCard() async {
        guard canAddCreditCard, !isSaving else { return }
        let draft = CreditCardDraft(
            bank: bank,
            lastFour: lastFour,
            network: network,
            color: color,
            debtMode: debtMode,
            principalDebt: Self.amount(principalDebtText) ?? 0,
            secondDebt: debtMode == .dual ? Self.amount(secondDebtText) ?? 0 : 0,
            limit: AmountInput.decimal(from: limitText),
            cutoffDay: cutoffDay,
            dueDay: dueDay,
        )
        await save { () async throws(DomainError) in
            let created = try await addCredit.execute(draft)
            createdAccount = created.account
            createdCard = created.holder
        }
    }

    /// Restarts at the type step for "Add another".
    public func restart() {
        bank = ""
        lastFour = ""
        principalDebtText = "0.00"
        secondDebtText = "0.00"
        limitText = ""
        createdAccount = nil
        createdCard = nil
        path = []
    }

    public func createAccount(kind: AccountKind, name: String, bank: String?, currency: String, balanceText: String) async -> Bool {
        guard let balance = Self.amount(balanceText) else {
            errorMessage = String(localized: "Check the balance.", bundle: #bundle)
            return false
        }
        do {
            _ = try await addAccount.execute(kind: kind, name: name, bank: bank, balance: Money(balance, currency))
            errorMessage = nil
            await load()
            return true
        } catch {
            errorMessage = String(localized: "We couldn't save the account.", bundle: #bundle)
            return false
        }
    }

    // MARK: Copy

    public var plasticTitle: String {
        kind == .credit
            ? String(localized: "Your credit card", bundle: #bundle)
            : String(localized: "Your debit card", bundle: #bundle)
    }

    public func modeTitle(_ mode: DebtMode) -> String {
        let first = principal
        let other = second ?? first
        return switch mode {
        case .dual: String(localized: "Two currencies", bundle: #bundle)
        case .principal: String(localized: "Only \(first)", bundle: #bundle)
        case .second: String(localized: "Only \(other)", bundle: #bundle)
        }
    }

    private func principalSubtitle(_ principal: String) -> String {
        if principal == "USD" {
            return String(localized: "Everything is converted to dollars", bundle: #bundle)
        }
        return String(localized: "Everything is converted to \(principal)", bundle: #bundle)
    }

    public func modeSubtitle(_ mode: DebtMode) -> String {
        let first = principal
        let other = second ?? first
        return switch mode {
        case .dual: String(localized: "\(first) and \(other), paid separately", bundle: #bundle)
        case .principal: principalSubtitle(first)
        case .second: String(localized: "Everything in local currency", bundle: #bundle)
        }
    }

    /// The sentence under "Card added".
    public var summary: String {
        if kind == .debit {
            let account = context?.depositAccounts.first { $0.id == createdCard?.accountID }
            let accountName = [account?.bank, account?.name].compactMap(\.self).joined(separator: " ")
            return String(localized: "Linked to \(accountName).", bundle: #bundle)
        }
        let first = principal
        let other = second ?? first
        let debt = switch debtMode {
        case .dual: String(localized: "Debt in \(first) and \(other)", bundle: #bundle)
        case .principal: String(localized: "Debt in \(first)", bundle: #bundle)
        case .second: String(localized: "Debt in \(other)", bundle: #bundle)
        }
        let (cutoffDay, dueDay) = (cutoffDay, dueDay)
        let cycle = String(localized: "\(debt) · cutoff day \(cutoffDay) · due day \(dueDay).", bundle: #bundle)
        let days = context?.paymentReminderDaysBefore ?? 3
        let reminder = String(localized: "We'll remind you \(days) days before the due date.", bundle: #bundle)
        return "\(cycle) \(reminder)"
    }

    // MARK: Private

    private func saveDebit() async {
        guard let accountID = linkedAccountID else { return }
        let (lastFour, network, color) = (lastFour, network, color)
        await save { () async throws(DomainError) in
            createdCard = try await addDebit.execute(accountID: accountID, lastFour: lastFour, network: network, color: color)
            createdAccount = nil
        }
    }

    private func save(_ work: () async throws(DomainError) -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await work()
            errorMessage = nil
            path.append(.done)
        } catch {
            errorMessage = String(localized: "We couldn't add the card. Try again.", bundle: #bundle)
        }
    }

    /// Days wrap 1 ↔ 31 like the design's steppers.
    static func wrapDay(_ day: Int) -> Int {
        day < 1 ? 31 : (day > 31 ? 1 : day)
    }

    static func amount(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : AmountInput.decimal(from: text)
    }
}
