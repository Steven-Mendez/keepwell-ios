import Domain
import Foundation

public protocol GetCashDetailUseCase: Sendable {
    func execute(accountID: UUID) async throws(DomainError) -> CashDetail
}

public struct DefaultGetCashDetailUseCase: GetCashDetailUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.categories = categories
        self.settings = settings
        self.calendar = calendar
    }

    public func execute(accountID: UUID) async throws(DomainError) -> CashDetail {
        let allAccounts = try await accounts.fetchAccounts()
        guard let account = allAccounts.first(where: { $0.id == accountID && $0.kind == .cash }) else {
            throw .notFound(accountID)
        }
        let currencies = try await settings.load()?.currencies ?? .fallback
        let movements = try await transactions.fetchTransactions(in: nil)
        let balance = Balances.balance(of: account, transactions: movements, calendar: calendar).first ?? .zero(currencies.principal)
        // No equivalent rather than a wrong one when the settings no longer convert the currency.
        let equivalent = balance.currency == currencies.principal
            ? nil
            : try? currencies.exchangeRate.convert(balance, to: currencies.principal)
        let touching = movements.filter(TransactionScope.account(account.id).includes)
        let latest = touching
            .filter(\.isConfirmed)
            .sorted { $0.date > $1.date }
            .prefix(CashDetail.latestCount)
        return try await CashDetail(
            account: account,
            balance: balance,
            principalEquivalent: equivalent,
            movementCount: touching.count,
            latestTransactions: Array(latest),
            accounts: allAccounts,
            cards: cards.fetchCards(),
            categories: categories.fetchCategories(),
        )
    }
}
