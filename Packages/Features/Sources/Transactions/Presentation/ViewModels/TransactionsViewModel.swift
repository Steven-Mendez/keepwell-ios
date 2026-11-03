import Domain
import Foundation
import Observation
import TransactionsDomain

@MainActor
@Observable
public final class TransactionsViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(DomainError)
    }

    public private(set) var month: YearMonth
    public private(set) var currency: String
    public private(set) var summary: MonthlySummary?
    public private(set) var transactions: [Transaction] = []
    public private(set) var state: LoadState = .idle
    /// Errors from user actions (delete) are shown as an alert without replacing the loaded content.
    public var actionError: DomainError?

    /// The selected currency stays listed even with no movements, so the picker never loses its selection.
    public var availableCurrencies: [String] {
        Set(transactions.map(\.currency)).union([currency]).sorted()
    }

    public var monthStart: Date? {
        month.dateInterval(in: calendar)?.start
    }

    @ObservationIgnored private let getMonthlySummary: any GetMonthlySummaryUseCase
    @ObservationIgnored private let getMonthlyTransactions: any GetMonthlyTransactionsUseCase
    @ObservationIgnored private let deleteTransaction: any DeleteTransactionUseCase
    @ObservationIgnored private let calendar: Calendar
    /// Lets a slow load for a month the user already left be discarded instead of overwriting newer data.
    @ObservationIgnored private var loadGeneration = 0

    public init(
        getMonthlySummary: any GetMonthlySummaryUseCase,
        getMonthlyTransactions: any GetMonthlyTransactionsUseCase,
        deleteTransaction: any DeleteTransactionUseCase,
        month: YearMonth,
        currency: String,
        calendar: Calendar = .current,
    ) {
        self.getMonthlySummary = getMonthlySummary
        self.getMonthlyTransactions = getMonthlyTransactions
        self.deleteTransaction = deleteTransaction
        self.month = month
        self.currency = currency
        self.calendar = calendar
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        do throws(DomainError) {
            let fetchedTransactions = try await getMonthlyTransactions.execute(month: month)
            let fetchedSummary = try await getMonthlySummary.execute(month: month, currency: currency)
            guard generation == loadGeneration else { return }
            transactions = fetchedTransactions
            summary = fetchedSummary
            state = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed(error)
        }
    }

    public func showPreviousMonth() async {
        month = month.adding(months: -1)
        await load()
    }

    public func showNextMonth() async {
        month = month.adding(months: 1)
        await load()
    }

    public func selectCurrency(_ newCurrency: String) async {
        guard newCurrency != currency else { return }
        currency = newCurrency
        await load()
    }

    public func delete(_ transaction: Transaction) async {
        do throws(DomainError) {
            try await deleteTransaction.execute(id: transaction.id)
            await load()
        } catch {
            actionError = error
        }
    }
}
