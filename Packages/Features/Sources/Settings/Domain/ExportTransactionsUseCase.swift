import Domain
import Foundation

/// "Export CSV": every movement as one row. Columns and values are a data format, not UI text,
/// so they stay in English with ISO dates and dot decimals whatever the device language is;
/// that keeps the file readable by any spreadsheet.
public protocol ExportTransactionsUseCase: Sendable {
    func execute() async throws(DomainError) -> String
}

public struct DefaultExportTransactionsUseCase: ExportTransactionsUseCase {
    private let transactions: any TransactionRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let personalDebts: (any PersonalDebtRepository)?

    /// With `personalDebts`, an expense with debts split from it reads `shared`.
    public init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        personalDebts: (any PersonalDebtRepository)? = nil,
    ) {
        self.transactions = transactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.personalDebts = personalDebts
    }

    public func execute() async throws(DomainError) -> String {
        try await Self.csv(
            transactions: transactions.fetchTransactions(in: nil),
            accounts: accounts.fetchAccounts(),
            cards: cards.fetchCards(),
            categories: categories.fetchCategories(),
            debts: personalDebts?.fetchPersonalDebts() ?? [],
        )
    }

    static let header = [
        "date", "status", "type", "description", "category", "amount", "currency", "account",
        "card_last_four", "destination_account", "debited_principal", "rate", "shared", "note", "tags",
    ]

    /// `debts` make an expense split from them read `shared` (`isSplit`); old rows' `isShared` still does.
    static func csv(
        transactions: [Transaction],
        accounts: [Account],
        cards: [Card],
        categories: [TransactionCategory],
        debts: [PersonalDebt] = [],
    ) -> String {
        let links = DebtLinks(debts)
        let accountNames = Dictionary(accounts.map { ($0.id, Self.name(of: $0)) }, uniquingKeysWith: { first, _ in first })
        let lastFour = Dictionary(cards.map { ($0.id, $0.lastFour ?? "") }, uniquingKeysWith: { first, _ in first })
        let categoryNames = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = transactions.sorted { $0.date < $1.date }.map { transaction in
            [
                Self.day(transaction.date),
                transaction.status.rawValue,
                transaction.kind.rawValue,
                Self.neutralized(transaction.description),
                Self.neutralized(transaction.categoryID.map { categoryNames[$0] ?? $0 } ?? ""),
                Self.number(transaction.amount),
                transaction.currency,
                Self.neutralized(accountNames[transaction.accountID] ?? ""),
                transaction.cardID.flatMap { lastFour[$0] } ?? "",
                Self.neutralized(transaction.destinationAccountID.flatMap { accountNames[$0] } ?? ""),
                transaction.actualDebitedPrincipal.map(Self.number) ?? "",
                transaction.exchangeRate.hasSecondCurrency ? Self.number(transaction.exchangeRate.rate) : "",
                transaction.isSplit(links) || transaction.isShared ? "yes" : "no",
                Self.neutralized(transaction.note ?? ""),
                Self.neutralized(Tags.csvField(transaction.tags)),
            ]
        }
        return ([header] + rows).map { $0.map(Self.escaped).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func name(of account: Account) -> String {
        [account.bank, account.name].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The day in the device's calendar ("2026-10-22"), since that's the day the person saw.
    private static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func number(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }

    /// Free text the person typed (descriptions, notes, tags, account and category names): a leading
    /// `'` keeps a spreadsheet from running a value that starts like a formula (`=`, `+`, `-`, `@`, tab
    /// or carriage return). Amounts, dates and rates never go through here, so a negative amount stays
    /// a number. Scalars, not characters, because "\r\n" is a single `Character`.
    static func neutralized(_ field: String) -> String {
        guard let first = field.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return field }
        return "'" + field
    }

    /// RFC 4180: quote fields with commas, quotes or line breaks, doubling inner quotes.
    static func escaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
