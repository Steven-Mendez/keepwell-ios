import Domain
import Foundation

/// What the add-card flow needs to know before it starts.
public struct AddCardContext: Sendable {
    public let currencies: CurrencySettings
    public let paymentReminderDaysBefore: Int

    public init(currencies: CurrencySettings, paymentReminderDaysBefore: Int) {
        self.currencies = currencies
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
    }
}

public protocol GetAddCardContextUseCase: Sendable {
    func execute() async throws(DomainError) -> AddCardContext
}

public struct DefaultGetAddCardContextUseCase: GetAddCardContextUseCase {
    private let settings: any SettingsRepository

    public init(settings: any SettingsRepository) {
        self.settings = settings
    }

    public func execute() async throws(DomainError) -> AddCardContext {
        let stored = try await settings.load()
        return AddCardContext(
            currencies: stored?.currencies ?? .fallbackForCards,
            paymentReminderDaysBefore: stored?.paymentReminderDaysBefore ?? 3,
        )
    }
}
