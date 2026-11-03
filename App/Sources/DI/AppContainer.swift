import Core
import Foundation
import SwiftData
import TransactionsData
import TransactionsDomain
import TransactionsPresentation

/// Composition root: the only place that names concrete types and wires Data → Domain → Presentation.
/// Features see protocols only, so swapping storage (e.g. for UI tests) is a change here alone.
final class AppContainer {
    /// Until currency settings exist: USD primary with NIO second, as in HANDOFF → "Monedas".
    let currencies = ["USD", "NIO"]
    let currencyFormatter = CurrencyFormatter()

    private let transactionRepository: any TransactionRepository
    private let calendar: Calendar

    init(transactionRepository: any TransactionRepository, calendar: Calendar = .autoupdatingCurrent) {
        self.transactionRepository = transactionRepository
        self.calendar = calendar
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(transactionRepository: SwiftDataTransactionRepository(modelContainer: modelContainer))
    }

    // MARK: - Transactions

    func makeTransactionsViewModel() -> TransactionsViewModel {
        TransactionsViewModel(
            getMonthlySummary: DefaultGetMonthlySummaryUseCase(repository: transactionRepository, calendar: calendar),
            getMonthlyTransactions: DefaultGetMonthlyTransactionsUseCase(repository: transactionRepository, calendar: calendar),
            deleteTransaction: DefaultDeleteTransactionUseCase(repository: transactionRepository),
            month: YearMonth(containing: .now, calendar: calendar),
            currency: currencies[0],
            calendar: calendar,
        )
    }

    func makeAddTransactionViewModel() -> AddTransactionViewModel {
        AddTransactionViewModel(
            addTransaction: DefaultAddTransactionUseCase(repository: transactionRepository),
            currencies: currencies,
        )
    }
}
