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
    /// A name the person must give (a card's or a category's) is empty.
    case missingName
    case invalidDayOfMonth(Int)
    /// Another category of the same kind already has this name.
    case duplicateCategoryName(String)
    /// "Other" and "Other income" take the movements of deleted categories, so they stay.
    case fallbackCategoryCantBeDeleted(String)
    case categoryKindMismatch(expected: TransactionKind, actual: TransactionKind)
    case unsupportedTransactionKind(TransactionKind)
    /// A transfer needs a destination account different from its source.
    case invalidTransferDestination
    /// The payment method can't be used: the card is frozen.
    case paymentMethodUnavailable(UUID)
    case invalidPeriod
    case notFound(UUID)
    /// An app passcode must be exactly `Passcode.length` digits.
    case invalidPasscode
    /// Repeated or consecutive digits ("111111", "123456") are the first ones anyone tries.
    case passcodeTooSimple
    case corruptedData(String)
    case persistence(String)
}
