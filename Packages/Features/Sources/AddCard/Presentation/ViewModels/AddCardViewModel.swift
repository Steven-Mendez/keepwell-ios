import AddCardDomain
import Core
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives "Add card": type → plastic → debt and cycle (credit only) → added. A debit card is a
/// bank account seen as its card, so the debit plastic step also asks for the account's name and
/// balance and creates both at once.
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
        case viewBankAccount(UUID)
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
    /// `nil` is "Not set": a card needn't have a billing cycle.
    public private(set) var cutoffDay: Int?
    public private(set) var dueDay: Int?
    /// Debit only: the bank account the card is.
    public var accountName = ""
    public var accountCurrency = ""
    public var balanceText = ""
    public private(set) var context: AddCardContext?
    public private(set) var createdAccount: Account?
    public private(set) var createdCard: Card?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// The person's own name, printed on their main cards.
    public private(set) var ownerName: String?

    private let getContext: any GetAddCardContextUseCase
    private let addCredit: any AddCreditCardUseCase
    private let addAccount: any AddAccountUseCase
    private let getPreferredName: any GetPreferredNameUseCase

    public init(
        getContext: any GetAddCardContextUseCase,
        addCredit: any AddCreditCardUseCase,
        addAccount: any AddAccountUseCase,
        getPreferredName: any GetPreferredNameUseCase,
    ) {
        self.getPreferredName = getPreferredName
        self.getContext = getContext
        self.addCredit = addCredit
        self.addAccount = addAccount
    }

    /// The owner's name as the new plastic prints it.
    public var printedName: String? {
        CardDisplay.holderName(of: nil, kind: kind == .credit ? .creditHolder : .debit, ownerName: ownerName)
    }

    public func load() async {
        ownerName = await getPreferredName.execute()
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

    public func choose(_ kind: Kind) {
        self.kind = kind
        network = kind == .credit ? .mastercard : .visa
        color = kind == .credit ? .azul : .verde
        errorMessage = nil
        path = [.plastic]
    }

    public var isLastFourValid: Bool {
        lastFour.count == 4 && lastFour.allSatisfy(\.isNumber)
    }

    public var canContinueFromPlastic: Bool {
        isLastFourValid &&
            (kind == .credit || (!accountName.trimmingCharacters(in: .whitespaces).isEmpty && Self.amount(balanceText) != nil))
    }

    /// The bank account's currency: the one picked, or the principal one.
    public var accountCurrencyCode: String {
        accountCurrency.isEmpty ? principal : accountCurrency
    }

    /// Credit cards go on to debt and cycle; debit cards are saved right away.
    public func continueFromPlastic() async {
        guard canContinueFromPlastic else { return }
        switch kind {
        case .credit: path.append(.debt)
        case .debit: await saveDebit()
        }
    }

    /// Where a day starts once the person chooses to set it: a typical cycle, not their first tap's direction.
    static let startingCutoffDay = 28
    static let startingDueDay = 15

    public func stepCutoff(by delta: Int) {
        cutoffDay = cutoffDay.map { Self.wrapDay($0 + delta) } ?? Self.startingCutoffDay
    }

    public func stepDue(by delta: Int) {
        dueDay = dueDay.map { Self.wrapDay($0 + delta) } ?? Self.startingDueDay
    }

    public func clearCutoff() {
        cutoffDay = nil
    }

    public func clearDue() {
        dueDay = nil
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
        accountName = ""
        accountCurrency = ""
        balanceText = ""
        createdAccount = nil
        createdCard = nil
        path = []
    }

    /// "Other wallet": cash and the like, which have no card.
    public func createWallet(name: String, currency: String, balanceText: String) async -> Bool {
        guard let balance = Self.amount(balanceText) else {
            errorMessage = String(localized: "Check the balance.", bundle: #bundle)
            return false
        }
        do {
            _ = try await addAccount.execute(kind: .cash, name: name, bank: nil, balance: Money(balance, currency))
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
            let name = createdAccount.map(CardDisplay.name(of:)) ?? accountName
            return String(localized: "\(name) is ready: this card is the account, with its balance and movements.", bundle: #bundle)
        }
        let first = principal
        let other = second ?? first
        let debt = switch debtMode {
        case .dual: String(localized: "Debt in \(first) and \(other)", bundle: #bundle)
        case .principal: String(localized: "Debt in \(first)", bundle: #bundle)
        case .second: String(localized: "Debt in \(other)", bundle: #bundle)
        }
        let cycle = switch (cutoffDay, dueDay) {
        case let (cutoff?, due?): String(localized: "\(debt) · cutoff day \(cutoff) · due day \(due).", bundle: #bundle)
        case let (cutoff?, nil): String(localized: "\(debt) · cutoff day \(cutoff).", bundle: #bundle)
        case let (nil, due?): String(localized: "\(debt) · due day \(due).", bundle: #bundle)
        case (nil, nil): String(localized: "\(debt).", bundle: #bundle)
        }
        // Without a due day there is nothing to remind about.
        guard dueDay != nil else { return cycle }
        let days = context?.paymentReminderDaysBefore ?? 3
        let reminder = String(localized: "We'll remind you \(days) days before the due date.", bundle: #bundle)
        return "\(cycle) \(reminder)"
    }

    // MARK: Private

    private func saveDebit() async {
        guard let balance = Self.amount(balanceText) else { return }
        let card = DebitCardDraft(lastFour: lastFour, network: network, color: color)
        let (name, bank, currency) = (accountName, bank, accountCurrencyCode)
        await save { () async throws(DomainError) in
            createdAccount = try await addAccount.execute(
                kind: .deposit,
                name: name,
                bank: bank.isEmpty ? nil : bank,
                balance: Money(balance, currency),
                debitCard: card,
            )
            createdCard = nil
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
