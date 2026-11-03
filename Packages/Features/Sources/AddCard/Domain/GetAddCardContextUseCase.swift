import Domain
import Foundation

/// What the add-card flow needs to know before it starts.
public struct AddCardContext: Sendable {
    public let currencies: CurrencySettings
    public let paymentReminderDaysBefore: Int
    /// Bank accounts a debit card can be linked to.
    public let depositAccounts: [Account]

    public init(currencies: CurrencySettings, paymentReminderDaysBefore: Int, depositAccounts: [Account]) {
        self.currencies = currencies
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
        self.depositAccounts = depositAccounts
    }
}

public protocol GetAddCardContextUseCase: Sendable {
    func execute() async throws(DomainError) -> AddCardContext
}

public struct DefaultGetAddCardContextUseCase: GetAddCardContextUseCase {
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository

    public init(settings: any SettingsRepository, accounts: any AccountRepository) {
        self.settings = settings
        self.accounts = accounts
    }

    public func execute() async throws(DomainError) -> AddCardContext {
        let stored = try await settings.load()
        return try await AddCardContext(
            currencies: stored?.currencies ?? .fallbackForCards,
            paymentReminderDaysBefore: stored?.paymentReminderDaysBefore ?? 3,
            depositAccounts: accounts.fetchAccounts().filter { $0.kind == .deposit },
        )
    }
}
