import Foundation

public enum AccountKind: String, Codable, CaseIterable, Sendable {
    /// Bank account; debit cards and transfers are linked to it.
    case deposit
    /// Cash, filled by transfers from a bank account.
    case cash
    /// A credit card is its own account: its balance is what is owed (negative).
    case credit
}

/// How a credit card bills.
public enum DebtMode: String, Codable, CaseIterable, Sendable {
    /// Separate debts in the principal and second currency, paid separately.
    case dual
    /// Everything converted to the principal currency.
    case principal
    /// Everything in the second currency.
    case second
}

/// Optional billing data of a credit account.
public struct CreditTerms: Hashable, Sendable, Codable {
    public let debtMode: DebtMode
    public let limit: Money?
    /// Day of month the statement closes (1–31; short months clamp to their last day).
    public let cutoffDay: Int?
    /// Day of month the payment is due.
    public let dueDay: Int?

    public init(debtMode: DebtMode, limit: Money? = nil, cutoffDay: Int? = nil, dueDay: Int? = nil) throws(DomainError) {
        for day in [cutoffDay, dueDay].compactMap(\.self) where !(1 ... 31).contains(day) {
            throw .invalidDayOfMonth(day)
        }
        self.debtMode = debtMode
        self.limit = limit
        self.cutoffDay = cutoffDay
        self.dueDay = dueDay
    }
}

public struct Account: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let bank: String?
    public let kind: AccountKind
    /// Balances on `openingDate`, one per currency the account holds (two for a dual credit card).
    /// Signed: credit debts are negative.
    public let openingBalances: [Money]
    /// Movements dated before this day are already part of `openingBalances`.
    public let openingDate: Date
    public let creditTerms: CreditTerms?
    /// When it was closed (`CloseAccountUseCase`); nil while open. A closed account keeps its
    /// movements and still counts in totals, but leaves lists and pickers until it is reopened.
    public let closedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        bank: String? = nil,
        kind: AccountKind,
        openingBalances: [Money],
        openingDate: Date,
        creditTerms: CreditTerms? = nil,
        closedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.bank = bank
        self.kind = kind
        self.openingBalances = openingBalances
        self.openingDate = openingDate
        self.creditTerms = creditTerms
        self.closedAt = closedAt
    }

    /// Open until `CloseAccountUseCase` stamps `closedAt`; `ReopenAccountUseCase` clears it.
    public var isOpen: Bool {
        closedAt == nil
    }

    /// The same account closed at `closedAt`, or open again with nil.
    public func with(closedAt: Date?) -> Self {
        Self(
            id: id, name: name, bank: bank, kind: kind, openingBalances: openingBalances,
            openingDate: openingDate, creditTerms: creditTerms, closedAt: closedAt,
        )
    }

    /// The currencies this account keeps a balance in, principal first for dual cards.
    public var currencies: [String] {
        openingBalances.map(\.currency)
    }
}

extension [Account] {
    /// The accounts lists and pickers offer. Totals (net worth, summaries) still read every
    /// account: a closed one keeps the history it had.
    public var open: [Account] {
        filter(\.isOpen)
    }
}
