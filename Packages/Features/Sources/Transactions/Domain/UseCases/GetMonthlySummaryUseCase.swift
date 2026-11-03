import Domain
import Foundation

public protocol GetMonthlySummaryUseCase: Sendable {
    func execute(month: YearMonth, currency: String) async throws(DomainError) -> MonthlySummary
}

public struct DefaultGetMonthlySummaryUseCase: GetMonthlySummaryUseCase {
    private let repository: any TransactionRepository
    private let calendar: Calendar

    public init(repository: any TransactionRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    public func execute(month: YearMonth, currency: String) async throws(DomainError) -> MonthlySummary {
        guard let period = month.dateInterval(in: calendar) else { throw .invalidPeriod }
        let transactions = try await repository.fetchTransactions(in: period)
        return Self.summarize(transactions, month: month, period: period, currency: currency)
    }

    /// HANDOFF rules 1, 4 and 7: only confirmed income/expense count; transfers move money between
    /// accounts and are neither. The period is re-checked here so the result never depends on how
    /// strictly a repository filters.
    static func summarize(
        _ transactions: [Transaction],
        month: YearMonth,
        period: DateInterval,
        currency: String,
    ) -> MonthlySummary {
        var income = Decimal.zero
        var expense = Decimal.zero
        for transaction in transactions
            where transaction.status == .confirmed
            && transaction.currency == currency
            && transaction.date >= period.start
            && transaction.date < period.end
        {
            switch transaction.kind {
            case .income: income += transaction.amount
            case .expense: expense += transaction.amount
            case .transfer: break
            }
        }
        let net = income - expense
        let savingsRate: Decimal? = income > 0 ? (net / income).rounded(scale: 4) : nil
        return MonthlySummary(
            month: month,
            currency: currency,
            totalIncome: income,
            totalExpense: expense,
            netBalance: net,
            savingsRate: savingsRate,
        )
    }
}
