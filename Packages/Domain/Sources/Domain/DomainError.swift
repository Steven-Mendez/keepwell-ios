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
    /// A card's "valid thru" needs a month 1–12 and a four-digit year.
    case invalidExpiry
    /// A savings goal's target month needs a month 1–12 and a year 2000–2199, like a card's expiry.
    case invalidTargetMonth
    /// Another category of the same kind already has this name.
    case duplicateCategoryName(String)
    /// "Other" and "Other income" take the movements of deleted categories, so they stay.
    case fallbackCategoryCantBeDeleted(String)
    case categoryKindMismatch(expected: TransactionKind, actual: TransactionKind)
    case unsupportedTransactionKind(TransactionKind)
    /// A transfer needs a destination account different from its source.
    case invalidTransferDestination
    case invalidPeriod
    /// A recurring rule repeats every 1 to 99 weeks, months or years.
    case invalidInterval(Int)
    /// A recurring rule can't end on a day before it starts.
    case invalidEndDate
    /// A personal debt can't be due before the day it was lent or borrowed.
    case invalidDueDate
    /// An account with money left can't close without a transfer that empties it.
    case accountNotEmpty(UUID)
    /// A closed account's balance stays as it was closed: nothing new is recorded in it until it is reopened.
    case accountClosed(UUID)
    case notFound(UUID)
    /// An app passcode must be exactly `Passcode.length` digits.
    case invalidPasscode
    /// Repeated or consecutive digits ("111111", "123456") are the first ones anyone tries.
    case passcodeTooSimple
    case corruptedData(String)
    case persistence(String)
}
