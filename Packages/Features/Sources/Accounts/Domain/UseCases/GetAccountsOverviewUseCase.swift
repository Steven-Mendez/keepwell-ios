import Domain
import Foundation

public protocol GetAccountsOverviewUseCase: Sendable {
    func execute() async throws(DomainError) -> AccountsOverview
}

public struct DefaultGetAccountsOverviewUseCase: GetAccountsOverviewUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.settings = settings
        self.calendar = calendar
    }

    public func execute() async throws(DomainError) -> AccountsOverview {
        let currencies = try await settings.load()?.currencies ?? CurrencySettings.fallback
        let allAccounts = try await accounts.fetchAccounts()
        let allCards = try await cards.fetchCards()
        let movements = try await transactions.fetchTransactions(in: nil)
        return try Self.overview(
            accounts: allAccounts,
            cards: allCards,
            transactions: movements,
            currencies: currencies,
            calendar: calendar,
        )
    }

    static func overview(
        accounts: [Account],
        cards: [Card],
        transactions: [Transaction],
        currencies: CurrencySettings,
        calendar: Calendar,
    ) throws(DomainError) -> AccountsOverview {
        var creditCards: [AccountsOverview.CreditCard] = []
        var deposits: [AccountsOverview.Deposit] = []
        var cash: [AccountsOverview.Cash] = []
        var allBalances: [Money] = []

        for account in accounts {
            let balances = Balances.balance(of: account, transactions: transactions, calendar: calendar)
            allBalances += balances
            let accountCards = cards.filter { $0.accountID == account.id }
            switch account.kind {
            case .credit:
                creditCards.append(AccountsOverview.CreditCard(
                    account: account,
                    holder: accountCards.first { $0.kind == .creditHolder },
                    plasticCount: accountCards.count { $0.kind == .creditHolder || $0.kind == .creditAdditional },
                    balances: balances.reversed(),
                ))
            case .deposit:
                deposits.append(AccountsOverview.Deposit(
                    account: account,
                    balance: balances.first ?? .zero(currencies.principal),
                    methods: accountCards.filter { $0.kind == .debit } + accountCards.filter { $0.kind == .transfer },
                ))
            case .cash:
                let balance = balances.first ?? .zero(currencies.principal)
                let equivalent = balance.currency == currencies.principal
                    ? nil
                    : try? currencies.exchangeRate.convert(balance, to: currencies.principal)
                cash.append(AccountsOverview.Cash(account: account, balance: balance, principalEquivalent: equivalent))
            }
        }
        let netWorth = try NetWorth.total(of: allBalances, settings: currencies)
        return AccountsOverview(settings: currencies, netWorth: netWorth, creditCards: creditCards, deposits: deposits, cash: cash)
    }
}

extension CurrencySettings {
    /// USD with rate 1, for the moment between a fresh install and finished onboarding.
    static let fallback: CurrencySettings = {
        guard let settings = try? CurrencySettings() else { preconditionFailure("Default currency settings are valid") }
        return settings
    }()
}
