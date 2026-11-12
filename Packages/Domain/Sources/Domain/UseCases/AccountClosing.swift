import Foundation

// Closing an account: it leaves lists and pickers while its movements stay in every total. Port of
// keepwell-web `closeAccount`, `reopenAccount` and `closingPlan` (src/lib/domain/accounts.ts).

/// What closing an account would do, for the sheet that asks first.
public struct ClosingPlan: Hashable, Sendable {
    /// Balances that aren't zero, one per currency: what a closing transfer has to move.
    public let balances: [Money]
    /// Open accounts that hold every one of those currencies, where the balance can go.
    public let destinations: [Account]
    /// Active recurring rules from or to the account: closing pauses them.
    public let rulesToPause: [RecurringRule]
    /// Drafts those rules (paused ones too) left waiting: closing deletes them.
    public let draftsToDelete: [Transaction]

    public init(
        of account: Account,
        accounts: [Account],
        transactions: [Transaction],
        rules: [RecurringRule],
        calendar: Calendar,
    ) {
        let balances = Balances.balance(of: account, transactions: transactions, calendar: calendar).filter { $0.amount != 0 }
        self.balances = balances
        destinations = balances.isEmpty ? [] : accounts.open.filter { candidate in
            candidate.id != account.id && balances.allSatisfy { candidate.currencies.contains($0.currency) }
        }
        let touching = rules.filter { $0.accountID == account.id || $0.destinationAccountID == account.id }
        let ruleIDs = Set(touching.map(\.id))
        rulesToPause = touching.filter { !$0.isPaused }
        draftsToDelete = transactions.filter { movement in
            !movement.isConfirmed && movement.recurringID.map(ruleIDs.contains) == true
        }
    }
}

public protocol GetClosingPlanUseCase: Sendable {
    func execute(accountID: UUID) async throws(DomainError) -> ClosingPlan
}

/// Closes an account without deleting its history. Confirmed balances must be zero or move to
/// `transferTo` (open, another account, holding each currency): one confirmed transfer per currency
/// dated now, out of the account when it holds money, into it when it owes (a card payment).
/// Recurring rules from or to it are paused and their drafts deleted. Already closed: nothing.
public protocol CloseAccountUseCase: Sendable {
    /// `description` names the closing transfers, localized by the screen ("Closing transfer").
    @discardableResult
    func execute(accountID: UUID, transferTo: UUID?, description: String) async throws(DomainError) -> Account
}

/// Opens a closed account again. Paused rules stay paused and closing transfers stay recorded.
public protocol ReopenAccountUseCase: Sendable {
    func execute(accountID: UUID) async throws(DomainError)
}

public struct DefaultAccountClosingUseCase: GetClosingPlanUseCase, CloseAccountUseCase, ReopenAccountUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let transactions: any TransactionRepository
    private let recurringRules: any RecurringRuleRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        recurringRules: any RecurringRuleRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func execute(accountID: UUID) async throws(DomainError) -> ClosingPlan {
        let all = try await accounts.fetchAccounts()
        guard let account = all.first(where: { $0.id == accountID }) else { throw .notFound(accountID) }
        return try await ClosingPlan(
            of: account,
            accounts: all,
            transactions: transactions.fetchTransactions(in: nil),
            rules: recurringRules.fetchRecurringRules(),
            calendar: calendar,
        )
    }

    @discardableResult
    public func execute(accountID: UUID, transferTo: UUID?, description: String) async throws(DomainError) -> Account {
        let all = try await accounts.fetchAccounts()
        guard let account = all.first(where: { $0.id == accountID }) else { throw .notFound(accountID) }
        guard account.isOpen else { return account }
        let movements = try await transactions.fetchTransactions(in: nil)
        let plan = try await ClosingPlan(
            of: account, accounts: all, transactions: movements, rules: recurringRules.fetchRecurringRules(), calendar: calendar,
        )
        let date = now()
        // Everything is checked and built before the first write.
        let transfers = try await closingTransfers(of: account, plan: plan, to: transferTo, description: description, date: date)
        if !transfers.isEmpty {
            try await transactions.save(transfers)
        }
        for rule in plan.rulesToPause {
            try await recurringRules.save(rule.with(isPaused: true, nextDate: rule.nextDate))
        }
        for draft in plan.draftsToDelete {
            try await transactions.deleteTransaction(id: draft.id)
        }
        let closed = account.with(closedAt: date)
        try await accounts.save(closed)
        return closed
    }

    public func execute(accountID: UUID) async throws(DomainError) {
        guard let account = try await accounts.fetchAccounts().first(where: { $0.id == accountID }) else {
            throw .notFound(accountID)
        }
        guard !account.isOpen else { return }
        try await accounts.save(account.with(closedAt: nil))
    }

    private func closingTransfers(
        of account: Account,
        plan: ClosingPlan,
        to transferTo: UUID?,
        description: String,
        date: Date,
    ) async throws(DomainError) -> [Transaction] {
        guard !plan.balances.isEmpty else { return [] }
        guard let transferTo else { throw .accountNotEmpty(account.id) }
        guard let destination = plan.destinations.first(where: { $0.id == transferTo }) else { throw .invalidTransferDestination }
        let currencies = try await settings.load()?.currencies ?? .initial
        let channels = try await cards.fetchCards().filter { $0.kind == .transfer }
        var transfers: [Transaction] = []
        for balance in plan.balances {
            try Transaction.checkCurrency(balance.currency, currencies: currencies)
            let leaving = balance.amount > 0
            let from = leaving ? account.id : destination.id
            let to = leaving ? destination.id : account.id
            transfers.append(Transaction(
                date: date,
                description: description,
                kind: .transfer,
                categoryID: nil,
                amount: abs(balance.amount),
                currency: balance.currency,
                accountID: from,
                cardID: channels.first { $0.accountID == from }?.id,
                destinationAccountID: to,
                exchangeRate: currencies.exchangeRate,
            ))
        }
        return transfers
    }
}
