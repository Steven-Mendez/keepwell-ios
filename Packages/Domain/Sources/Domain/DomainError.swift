import Foundation

/// The closed set of failures repositories and use cases may raise (`throws(DomainError)`), so
/// callers handle each case explicitly instead of inspecting `any Error`.
/// Associated messages are diagnostics for logs, not user-facing text.
public enum DomainError: Error, Equatable, Sendable {
    case invalidAmount
    case invalidCurrency(String)
    /// Two amounts in different currencies were combined without a conversion.
    case currencyMismatch(String, String)
    /// Rates are "1 principal = X second" and must be positive.
    case invalidExchangeRate
    case invalidLastFour(String)
    case invalidDayOfMonth(Int)
    case categoryKindMismatch(expected: TransactionKind, actual: TransactionKind)
    case unsupportedTransactionKind(TransactionKind)
    /// A transfer needs a destination account different from its source.
    case invalidTransferDestination
    case invalidPeriod
    case notFound(UUID)
    case corruptedData(String)
    case persistence(String)
}
