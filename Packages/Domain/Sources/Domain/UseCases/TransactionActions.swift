import Foundation

// Actions on a single movement shared by several screens (home, the movement list, a card's
// cycle). They live in the kernel because features can't depend on each other.

/// Turns a planned movement into a confirmed one, so it starts counting toward balances (rule 1).
public protocol ConfirmPlannedTransactionUseCase: Sendable {
    func execute(id: UUID) async throws(DomainError)
}

public struct DefaultConfirmPlannedTransactionUseCase: ConfirmPlannedTransactionUseCase {
    private let transactions: any TransactionRepository
    private let accounts: (any AccountRepository)?
    private let now: @Sendable () -> Date

    /// `now` dates a planned movement that was due in the future to the day it actually happened.
    /// With `accounts`, a draft of a closed account stays a draft (`accountClosed`).
    public init(
        transactions: any TransactionRepository,
        accounts: (any AccountRepository)? = nil,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.transactions = transactions
        self.accounts = accounts
        self.now = now
    }

    public func execute(id: UUID) async throws(DomainError) {
        guard let planned = try await transactions.fetchTransactions(in: nil).first(where: { $0.id == id }) else {
            throw .notFound(id)
        }
        guard !planned.isConfirmed else { return }
        let today = now()
        let confirmed = planned.date > today ? planned.confirmed().with(date: today) : planned.confirmed()
        if let accounts {
            try await Transaction.checkClosedAccounts(confirmed, existing: planned, accounts: accounts.fetchAccounts())
        }
        try await transactions.save(confirmed)
    }
}

/// Undoes `ConfirmPlannedTransactionUseCase`: the movement is a draft again, back on the date it was
/// planned for (confirming may have moved it to today), so it stops counting toward balances.
public protocol UnconfirmTransactionUseCase: Sendable {
    func execute(id: UUID, plannedDate: Date) async throws(DomainError)
}

public struct DefaultUnconfirmTransactionUseCase: UnconfirmTransactionUseCase {
    private let transactions: any TransactionRepository
    private let accounts: (any AccountRepository)?

    /// With `accounts`, a movement of a closed account stays confirmed (`accountClosed`).
    public init(transactions: any TransactionRepository, accounts: (any AccountRepository)? = nil) {
        self.transactions = transactions
        self.accounts = accounts
    }

    public func execute(id: UUID, plannedDate: Date) async throws(DomainError) {
        guard let confirmed = try await transactions.fetchTransactions(in: nil).first(where: { $0.id == id }) else {
            throw .notFound(id)
        }
        guard confirmed.isConfirmed else { return }
        let planned = confirmed.with(status: .planned).with(date: plannedDate)
        if let accounts {
            try await Transaction.checkClosedAccounts(planned, existing: confirmed, accounts: accounts.fetchAccounts())
        }
        try await transactions.save(planned)
    }
}

public protocol DeleteTransactionUseCase: Sendable {
    func execute(id: UUID) async throws(DomainError)
}

public struct DefaultDeleteTransactionUseCase: DeleteTransactionUseCase {
    private let transactions: any TransactionRepository

    public init(transactions: any TransactionRepository) {
        self.transactions = transactions
    }

    public func execute(id: UUID) async throws(DomainError) {
        try await transactions.deleteTransaction(id: id)
    }
}

extension Transaction {
    public func with(date: Date) -> Self {
        Self(
            id: id, date: date, status: status, description: description, kind: kind, categoryID: categoryID,
            amount: amount, currency: currency, accountID: accountID, cardID: cardID,
            destinationAccountID: destinationAccountID, actualDebitedPrincipal: actualDebitedPrincipal,
            exchangeRate: exchangeRate, isShared: isShared, note: note, recurringID: recurringID, tags: tags,
            source: source, merchantID: merchantID, viaMerchantID: viaMerchantID,
        )
    }
}
