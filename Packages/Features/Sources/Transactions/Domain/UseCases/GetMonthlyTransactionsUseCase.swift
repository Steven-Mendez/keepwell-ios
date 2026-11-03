import Domain
import Foundation

public protocol GetMonthlyTransactionsUseCase: Sendable {
    /// All currencies and statuses (planned included), newest first: the list shows everything,
    /// only the summary filters.
    func execute(month: YearMonth) async throws(DomainError) -> [Transaction]
}

public struct DefaultGetMonthlyTransactionsUseCase: GetMonthlyTransactionsUseCase {
    private let repository: any TransactionRepository
    private let calendar: Calendar

    public init(repository: any TransactionRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    public func execute(month: YearMonth) async throws(DomainError) -> [Transaction] {
        guard let period = month.dateInterval(in: calendar) else { throw .invalidPeriod }
        return try await repository.fetchTransactions(in: period)
            .filter { $0.date >= period.start && $0.date < period.end }
            .sorted { $0.date > $1.date }
    }
}
