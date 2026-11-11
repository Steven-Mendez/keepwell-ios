import Domain
import Foundation

/// Balances and movements are kept in their own currency, so a currency can only change while
/// nothing is kept in it.
public enum CurrencyUsage {
    /// The main currency can change only on an empty ledger: no accounts and no movements.
    public static func canChangeMain(accounts: [Account], transactions: [Transaction]) -> Bool {
        accounts.isEmpty && transactions.isEmpty
    }

    /// The second currency (or none) can change while no account balance or movement uses it.
    public static func canChangeSecond(
        _ second: String?,
        accounts: [Account],
        transactions: [Transaction],
    ) -> Bool {
        guard let second else { return true }
        return !accounts.contains { $0.currencies.contains(second) } && !transactions.contains { $0.currency == second }
    }
}

public enum CurrencyChange: Hashable, Sendable {
    case main(String)
    /// `nil` goes back to a single currency.
    case second(String?)
}

/// Changes the main or the second currency, refusing while the current one is still in use.
public protocol ChangeCurrenciesUseCase: Sendable {
    func execute(_ change: CurrencyChange) async throws(DomainError)
}

public struct DefaultChangeCurrenciesUseCase: ChangeCurrenciesUseCase {
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository

    public init(
        settings: any SettingsRepository,
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
    ) {
        self.settings = settings
        self.accounts = accounts
        self.transactions = transactions
    }

    public func execute(_ change: CurrencyChange) async throws(DomainError) {
        var current = try await settings.load() ?? Settings(currencies: .initial)
        let allAccounts = try await accounts.fetchAccounts()
        let allTransactions = try await transactions.fetchTransactions(in: nil)
        let currencies = current.currencies
        switch change {
        case let .main(code):
            guard CurrencyUsage.canChangeMain(accounts: allAccounts, transactions: allTransactions) else {
                throw .invalidCurrency(currencies.principal)
            }
            guard ISOCurrency.isValid(code) else { throw .invalidCurrency(code) }
            current.currencies = try CurrencySettings(principal: code, second: currencies.second, rate: currencies.rate)
        case let .second(code):
            guard CurrencyUsage.canChangeSecond(currencies.second, accounts: allAccounts, transactions: allTransactions) else {
                throw .invalidCurrency(currencies.second ?? "")
            }
            if let code, !ISOCurrency.isValid(code) {
                throw .invalidCurrency(code)
            }
            // A different second currency starts at rate 1: the old rate belonged to the old one.
            let rate = code == currencies.second ? currencies.rate : 1
            current.currencies = try CurrencySettings(principal: currencies.principal, second: code, rate: rate)
        }
        try await settings.save(current)
    }
}
