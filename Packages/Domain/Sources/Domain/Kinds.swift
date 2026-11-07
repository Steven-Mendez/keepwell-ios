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

/// Who created a movement or rule: the person in an app, or an MCP client such as Claude. Set when
/// it is created and never changed, so confirming Claude's movement still shows who recorded it.
public enum RecordSource: String, Codable, CaseIterable, Sendable {
    case app
    case mcp
}
