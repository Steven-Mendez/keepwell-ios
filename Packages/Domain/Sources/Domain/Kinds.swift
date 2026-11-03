/// Transfers move money between accounts and are neither expense nor income.
public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case transfer
}

/// `planned` transactions don't count toward balances or summaries until confirmed.
public enum TransactionStatus: String, Codable, CaseIterable, Sendable {
    case confirmed
    case planned
}
