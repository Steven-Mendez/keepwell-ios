import Foundation

/// The closed set of failures repositories and use cases may raise (`throws(DomainError)`), so
/// callers handle each case explicitly instead of inspecting `any Error`.
/// Associated messages are diagnostics for logs, not user-facing text.
public enum DomainError: Error, Equatable, Sendable {
    case invalidAmount
    case invalidCurrency(String)
    case categoryKindMismatch(expected: TransactionKind, actual: TransactionKind)
    /// Transfers need source and destination accounts, which this model doesn't have yet.
    case unsupportedTransactionKind(TransactionKind)
    case invalidPeriod
    case notFound(UUID)
    case corruptedData(String)
    case persistence(String)
}
