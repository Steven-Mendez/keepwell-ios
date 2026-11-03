import Core
import Domain
import Foundation
import Observation
import SharedPresentation
import TransactionsDomain

@MainActor
@Observable
public final class TransactionsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(TransactionList)
        case failed
    }

    public struct Section: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let transactions: [Transaction]
    }

    public private(set) var state = State.loading
    public var filter = TransactionFilter.all
    /// The account or card the list is narrowed to; `.all` shows every movement.
    public var scope = TransactionScope.all
    public var query = ""
    /// Set by whoever opens the list to search ("Search transactions" on home); the view focuses
    /// the field and clears it.
    public var wantsSearchFocus = false
    public private(set) var actionError: String?

    private let getList: any GetTransactionListUseCase
    private let confirmPlanned: any ConfirmPlannedTransactionUseCase
    private let deleteTransaction: any DeleteTransactionUseCase
    private let filterTransactions: any FilterTransactionsUseCase
    private let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    public init(
        getList: any GetTransactionListUseCase,
        confirmPlanned: any ConfirmPlannedTransactionUseCase,
        deleteTransaction: any DeleteTransactionUseCase,
        filterTransactions: any FilterTransactionsUseCase = DefaultFilterTransactionsUseCase(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.getList = getList
        self.confirmPlanned = confirmPlanned
        self.deleteTransaction = deleteTransaction
        self.filterTransactions = filterTransactions
        self.calendar = calendar
        self.now = now
    }

    public var list: TransactionList? {
        if case let .loaded(list) = state {
            list
        } else {
            nil
        }
    }

    public func load() async {
        do {
            state = try await .loaded(getList.execute())
        } catch {
            state = .failed
        }
    }

    public func confirm(_ id: UUID) async {
        await perform { () async throws(DomainError) in try await confirmPlanned.execute(id: id) }
    }

    public func delete(_ id: UUID) async {
        await perform { () async throws(DomainError) in try await deleteTransaction.execute(id: id) }
    }

    private func perform(_ action: () async throws(DomainError) -> Void) async {
        do {
            try await action()
            actionError = nil
            await load()
        } catch {
            actionError = String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
        }
    }

    // MARK: - Display

    var display: TransactionDisplay? {
        list.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    public var hasTransactions: Bool {
        list?.transactions.isEmpty == false
    }

    private var transactionQuery: TransactionQuery {
        TransactionQuery(kind: filter, scope: scope, text: query)
    }

    /// What the chips, the account filter and the search leave visible, newest first.
    func visibleTransactions(ignoringKind: Bool = false) -> [Transaction] {
        guard let list, let display else { return [] }
        var query = transactionQuery
        if ignoringKind {
            query.kind = .all
        }
        return filterTransactions.execute(list.transactions, matching: query, searchableText: display.searchableText(of:))
    }

    /// Planned movements first, then confirmed ones grouped by day, newest first.
    public var sections: [Section] {
        let visible = visibleTransactions()
        var sections: [Section] = []
        let planned = visible.filter { !$0.isConfirmed }.sorted { $0.date < $1.date }
        if !planned.isEmpty {
            sections.append(Section(
                id: "planned",
                title: String(localized: "Planned · they don't affect balances", bundle: #bundle),
                transactions: planned,
            ))
        }
        var current: (day: Date, items: [Transaction])?
        for transaction in visible where transaction.isConfirmed {
            let day = calendar.startOfDay(for: transaction.date)
            if current?.day == day {
                current?.items.append(transaction)
            } else {
                if let current {
                    sections.append(daySection(current.day, current.items))
                }
                current = (day, [transaction])
            }
        }
        if let current {
            sections.append(daySection(current.day, current.items))
        }
        return sections
    }

    private func daySection(_ day: Date, _ items: [Transaction]) -> Section {
        Section(id: day.ISO8601Format(), title: dayTitle(day), transactions: items)
    }

    /// "22 October", with the year only when it isn't this year's.
    func dayTitle(_ day: Date) -> String {
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now())
        return sameYear
            ? day.formatted(.dateTime.day().month(.wide))
            : day.formatted(.dateTime.day().month(.wide).year())
    }

    /// "October 2026", "−$709.58" and "+$2,452.24" for the current month's confirmed movements of
    /// the chosen account and search, apart so the view can color what went out and what came in.
    /// The kind chips don't change it: they pick which rows to read within the same month. Amounts
    /// are converted to the principal currency, never mixed.
    var monthTotals: (title: String, spent: String, earned: String)? {
        guard let list else { return nil }
        let month = YearMonth(containing: now(), calendar: calendar)
        let summary = MonthlySummary(
            month: month,
            transactions: visibleTransactions(ignoringKind: true),
            currency: list.settings.principal,
            calendar: calendar,
        )
        let title = now().formatted(.dateTime.month(.wide).year()).localizedCapitalized
        let spent = formatter.string(from: -summary.expense, currencyCode: summary.currency)
        let earned = formatter.string(from: summary.income, currencyCode: summary.currency, sign: .always)
        return (title, spent, earned)
    }

    // MARK: - Account filter

    public var scopeGroups: [TransactionScopeGroup] {
        list?.scopeGroups ?? []
    }

    /// The account filter chip: "All accounts", "Savings" or "Debit •••• 1234".
    var scopeTitle: String {
        guard let list else { return String(localized: "All accounts", bundle: #bundle) }
        switch scope {
        case .all:
            return String(localized: "All accounts", bundle: #bundle)
        case .account:
            return list.account(in: scope).map(CardDisplay.name(of:)) ?? String(localized: "All accounts", bundle: #bundle)
        case .card:
            guard let card = list.card(in: scope) else { return String(localized: "All accounts", bundle: #bundle) }
            return CardDisplay.methodTitle(card, account: list.account(in: scope))
        }
    }

    func cardTitle(_ card: Card, in group: TransactionScopeGroup) -> String {
        CardDisplay.methodTitle(card, account: group.account)
    }

    /// The balance behind the chosen account or card, LAFISE-style: "Available balance" for money
    /// the person holds, "Current debt" (as an amount owed) for a credit card, as the card's own
    /// screen shows it. A single-currency account shows its own currency (cash in córdobas stays
    /// in córdobas); one in two currencies headlines the principal-currency total and
    /// lists each currency under it. `nil` without an account filter.
    var scopeBalance: (label: String, amount: String, details: [String])? {
        guard let list, let account = list.account(in: scope),
              let balances = list.balances(in: scope, calendar: calendar),
              let total = list.balanceTotal(in: scope, calendar: calendar) else { return nil }
        let isCredit = account.kind == .credit
        let shown: (Money) -> String = { money in
            self.formatter.string(isCredit ? Money(-money.amount, money.currency) : money)
        }
        let label = isCredit
            ? String(localized: "Current debt", bundle: #bundle)
            : String(localized: "Available balance", bundle: #bundle)
        guard balances.count > 1 else { return (label, balances.first.map(shown) ?? shown(total), []) }
        return (label, shown(total), (isCredit ? balances.reversed() : balances).map(shown))
    }

    /// Shown when an account has nothing yet, so it doesn't read as a search that failed.
    var isScopeEmpty: Bool {
        scope != .all && query.trimmingCharacters(in: .whitespaces).isEmpty && filter == .all && visibleTransactions().isEmpty
    }

    func filterTitle(_ filter: TransactionFilter) -> String {
        switch filter {
        case .all: String(localized: "All", bundle: #bundle)
        case .expense: String(localized: "Expenses", bundle: #bundle)
        case .income: String(localized: "Income", bundle: #bundle)
        case .transfer: String(localized: "Transfers", bundle: #bundle)
        case .planned: String(localized: "Planned", bundle: #bundle)
        }
    }
}
