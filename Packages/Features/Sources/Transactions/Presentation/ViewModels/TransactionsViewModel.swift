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
    public var query = ""
    /// Set by whoever opens the list to search ("Search transactions" on home); the view focuses
    /// the field and clears it.
    public var wantsSearchFocus = false
    public private(set) var actionError: String?

    private let getList: any GetTransactionListUseCase
    private let confirmPlanned: any ConfirmPlannedTransactionUseCase
    private let deleteTransaction: any DeleteTransactionUseCase
    private let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    public init(
        getList: any GetTransactionListUseCase,
        confirmPlanned: any ConfirmPlannedTransactionUseCase,
        deleteTransaction: any DeleteTransactionUseCase,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.getList = getList
        self.confirmPlanned = confirmPlanned
        self.deleteTransaction = deleteTransaction
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

    /// Planned movements first, then confirmed ones grouped by day, newest first.
    public var sections: [Section] {
        guard let list, let display else { return [] }
        let needle = query.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let visible = list.transactions.filter { transaction in
            filter.matches(transaction) && (needle.isEmpty || display.searchableText(of: transaction).contains(needle))
        }
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

    /// "October 2026" and "−$709.58 · +$2,452.24" for the current month's confirmed movements.
    var monthTotals: (title: String, totals: String)? {
        guard let list else { return nil }
        let month = YearMonth(containing: now(), calendar: calendar)
        let summary = MonthlySummary(month: month, transactions: list.transactions, currency: list.settings.principal, calendar: calendar)
        let title = now().formatted(.dateTime.month(.wide).year()).localizedCapitalized
        let spent = formatter.string(from: -summary.expense, currencyCode: summary.currency)
        let earned = formatter.string(from: summary.income, currencyCode: summary.currency, sign: .always)
        return (title, "\(spent) · \(earned)")
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
