import Domain
import Foundation

/// An account as typed during onboarding, before it becomes an `Account` and its cards.
public struct OnboardingAccountDraft: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable {
        case bank
        case credit
        case cash
    }

    public let id: UUID
    public var kind: Kind
    public var name: String
    public var bank: String?
    /// Bank and cash accounts hold one currency; credit cards follow `debtMode`.
    public var currency: String
    /// Today's balance. For credit cards, what is owed (positive), in the principal currency or
    /// the only currency of the card.
    public var balance: Decimal
    /// Dual credit cards: what is owed in the second currency.
    public var secondBalance: Decimal
    public var lastFour: String?
    public var network: CardNetwork?
    public var debtMode: DebtMode?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        name: String,
        bank: String? = nil,
        currency: String,
        balance: Decimal = 0,
        secondBalance: Decimal = 0,
        lastFour: String? = nil,
        network: CardNetwork? = nil,
        debtMode: DebtMode? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.bank = bank
        self.currency = currency
        self.balance = balance
        self.secondBalance = secondBalance
        self.lastFour = lastFour
        self.network = network
        self.debtMode = debtMode
    }

    /// "Banco Ahorro": the bank followed by the account's own name, as the lists show it.
    public var displayName: String {
        [bank, name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Everything onboarding collected.
public struct OnboardingDraft: Sendable {
    public var currencies: CurrencySettings
    public var accounts: [OnboardingAccountDraft]
    public var locksWithBiometrics: Bool
    public var backsUpToICloud: Bool
    public var hidesAmountsInAppSwitcher: Bool

    public init(
        currencies: CurrencySettings,
        accounts: [OnboardingAccountDraft],
        locksWithBiometrics: Bool = true,
        backsUpToICloud: Bool = true,
        hidesAmountsInAppSwitcher: Bool = true,
    ) {
        self.currencies = currencies
        self.accounts = accounts
        self.locksWithBiometrics = locksWithBiometrics
        self.backsUpToICloud = backsUpToICloud
        self.hidesAmountsInAppSwitcher = hidesAmountsInAppSwitcher
    }
}
