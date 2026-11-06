import Domain
import Foundation

/// Every movement with what's needed to describe it, newest first.
public struct TransactionList: Hashable, Sendable {
    public let settings: CurrencySettings
    public let transactions: [Transaction]
    public let accounts: [Account]
    public let cards: [Card]
    public let categories: [TransactionCategory]
    /// Live recurring rules, to name the one a movement came from.
    public let recurringRules: [RecurringRule]

    public init(
        settings: CurrencySettings,
        transactions: [Transaction],
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
        recurringRules: [RecurringRule] = [],
    ) {
        self.settings = settings
        self.transactions = transactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.recurringRules = recurringRules
    }

    /// The live rule that recorded the movement; `nil` when it was deleted since.
    public func recurringRule(of transaction: Transaction) -> RecurringRule? {
        transaction.recurringID.flatMap { id in recurringRules.first { $0.id == id } }
    }
}

/// The list's filter chips. Planned movements show only under `planned`, since they don't count
/// yet and would otherwise read as spending that already happened.
public enum TransactionFilter: String, CaseIterable, Sendable {
    case all
    case expense
    case income
    case transfer
    case planned

    public func matches(_ transaction: Transaction) -> Bool {
        switch self {
        case .all: true
        case .planned: !transaction.isConfirmed
        case .expense: transaction.isConfirmed && transaction.kind == .expense
        case .income: transaction.isConfirmed && transaction.kind == .income
        case .transfer: transaction.isConfirmed && transaction.kind == .transfer
        }
    }
}

public protocol GetTransactionListUseCase: Sendable {
    func execute() async throws(DomainError) -> TransactionList
}

public struct DefaultGetTransactionListUseCase: GetTransactionListUseCase {
    private let transactions: any TransactionRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let recurringRules: (any RecurringRuleRepository)?

    public init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        recurringRules: (any RecurringRuleRepository)? = nil,
    ) {
        self.transactions = transactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.settings = settings
        self.recurringRules = recurringRules
    }

    public func execute() async throws(DomainError) -> TransactionList {
        let currencies = try await settings.load()?.currencies ?? .initial
        return try await TransactionList(
            settings: currencies,
            transactions: transactions.fetchTransactions(in: nil).sorted { $0.date > $1.date },
            accounts: accounts.fetchAccounts(),
            cards: cards.fetchCards(),
            categories: categories.fetchCategories(),
            recurringRules: recurringRules?.fetchRecurringRules() ?? [],
        )
    }
}
