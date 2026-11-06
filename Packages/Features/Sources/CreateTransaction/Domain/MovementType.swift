import Domain
import Foundation

/// What the person is recording, as the entry sheet offers it. The three transfer shapes are all
/// `TransactionKind.transfer`; they only differ in which of the person's accounts may send and
/// receive, which is what lets the flow show a short, relevant list on each side.
public enum MovementType: String, CaseIterable, Hashable, Sendable {
    case expense
    case income
    /// Between the person's own bank accounts and cash.
    case transfer
    /// From a bank account into cash.
    case withdrawal
    /// From a bank account or cash into a credit card, lowering what is owed.
    case cardPayment

    public init(_ kind: TransactionKind) {
        switch kind {
        case .expense: self = .expense
        case .income: self = .income
        case .transfer: self = .transfer
        }
    }

    public var kind: TransactionKind {
        switch self {
        case .expense: .expense
        case .income: .income
        case .transfer, .withdrawal, .cardPayment: .transfer
        }
    }

    public var movesBetweenAccounts: Bool {
        kind == .transfer
    }

    /// Accounts money may leave from. Expenses and income pick a payment method instead, so every
    /// account qualifies there.
    public func allowsSource(_ account: Account) -> Bool {
        switch self {
        case .expense, .income: true
        case .transfer, .cardPayment: account.kind != .credit
        case .withdrawal: account.kind == .deposit
        }
    }

    public func allowsDestination(_ account: Account, from source: UUID?) -> Bool {
        guard account.id != source else { return false }
        return switch self {
        case .expense, .income: false
        case .transfer: account.kind != .credit
        case .withdrawal: account.kind == .cash
        case .cardPayment: account.kind == .credit
        }
    }

    /// The types that can actually be recorded with these accounts: a withdrawal needs a bank
    /// account and cash, a card payment needs a card and somewhere to pay it from.
    public static func available(with accounts: [Account]) -> [Self] {
        guard !accounts.isEmpty else { return [] }
        return allCases.filter { type in
            guard type.movesBetweenAccounts else { return true }
            return accounts.contains { source in
                type.allowsSource(source) && accounts.contains { type.allowsDestination($0, from: source.id) }
            }
        }
    }
}
