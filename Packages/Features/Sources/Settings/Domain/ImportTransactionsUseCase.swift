import Domain
import Foundation

/// What an import did, for the message after it.
public struct ImportSummary: Hashable, Sendable {
    public let imported: Int
    /// Rows with an unknown account, a bad date or amount, or that were already recorded.
    public let skipped: Int

    public init(imported: Int, skipped: Int) {
        self.imported = imported
        self.skipped = skipped
    }
}

/// "Import CSV": reads the file "Export CSV" writes (same columns, any order). Each row must name
/// an account that exists, so movements never land somewhere the person didn't choose; rows
/// already recorded are skipped, so importing the same file twice changes nothing. A row without a
/// category the app knows gets the first categorization rule its description or note matches.
public protocol ImportTransactionsUseCase: Sendable {
    func execute(csv: String) async throws(DomainError) -> ImportSummary
}

public struct DefaultImportTransactionsUseCase: ImportTransactionsUseCase {
    private let transactions: any TransactionRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let categories: any CategoryRepository
    private let settings: any SettingsRepository
    private let rules: (any CategorizationRuleRepository)?
    private let calendar: Calendar

    public init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        categories: any CategoryRepository,
        settings: any SettingsRepository,
        rules: (any CategorizationRuleRepository)? = nil,
        calendar: Calendar = .current,
    ) {
        self.transactions = transactions
        self.accounts = accounts
        self.cards = cards
        self.categories = categories
        self.settings = settings
        self.rules = rules
        self.calendar = calendar
    }

    public func execute(csv: String) async throws(DomainError) -> ImportSummary {
        let currencies = try await settings.load()?.currencies ?? .initial
        let records = try await LedgerRecords.load(accounts: accounts, cards: cards, transactions: transactions, categories: categories)
        let rules = try await rules?.fetchCategorizationRules() ?? []
        let parsed = Self.parse(csv: csv, records: records, currencies: currencies, rules: rules, calendar: calendar)
        for transaction in parsed.transactions {
            try await transactions.save(transaction)
        }
        return ImportSummary(imported: parsed.transactions.count, skipped: parsed.skipped)
    }

    static func parse(
        csv: String,
        records: LedgerRecords,
        currencies: CurrencySettings,
        rules: [CategorizationRule] = [],
        calendar: Calendar,
    ) -> (transactions: [Transaction], skipped: Int) {
        let rows = CSV.rows(csv)
        guard let header = rows.first else { return ([], 0) }
        let columns = Dictionary(header.enumerated()
            .map { ($0.element.lowercased().trimmingCharacters(in: .whitespaces), $0.offset) }) { first, _ in first }
        // A rule whose category was deleted since can't place anything.
        let usable = rules.filter { rule in records.categories.contains { $0.id == rule.categoryID && $0.kind == rule.kind } }
        let reader = RowReader(columns: columns, records: records, currencies: currencies, rules: usable, calendar: calendar)
        var seen = Set(records.transactions.map(Fingerprint.init))
        var imported: [Transaction] = []
        var skipped = 0
        for row in rows.dropFirst() where !row.allSatisfy(\.isEmpty) {
            guard let transaction = reader.transaction(from: row), seen.insert(Fingerprint(transaction)).inserted else {
                skipped += 1
                continue
            }
            imported.append(transaction)
        }
        return (imported, skipped)
    }
}

/// Turns one CSV row into a movement, or `nil` when it can't be placed safely.
private struct RowReader {
    let columns: [String: Int]
    let records: LedgerRecords
    let currencies: CurrencySettings
    let rules: [CategorizationRule]
    let calendar: Calendar

    func value(_ name: String, in row: [String]) -> String? {
        guard let index = columns[name], row.indices.contains(index) else { return nil }
        let trimmed = row[index].trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    func transaction(from row: [String]) -> Transaction? {
        guard let date = value("date", in: row).flatMap(day),
              let amount = value("amount", in: row).flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }),
              let account = value("account", in: row).flatMap(account(named:))
        else { return nil }
        let debited = value("debited_principal", in: row).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        guard (try? Transaction.checkAmounts(amount, actualDebitedPrincipal: debited)) != nil else { return nil }
        let kind = value("type", in: row).flatMap(TransactionKind.init(rawValue:)) ?? .expense
        let destination = value("destination_account", in: row).flatMap(account(named:))
        if kind == .transfer, destination == nil || destination?.id == account.id {
            return nil
        }
        let currency = (try? Money.normalizedCurrency(value("currency", in: row) ?? "")) ?? account.currencies.first ?? currencies.principal
        let lastFour = value("card_last_four", in: row)
        let card = lastFour.flatMap { digits in records.cards.first { $0.accountID == account.id && $0.lastFour == digits } }
        let description = value("description", in: row) ?? ""
        let note = value("note", in: row)
        var category = kind == .transfer ? nil : categoryID(value("category", in: row), kind: kind)
        var tags: [String] = []
        if kind != .transfer, category == nil {
            let rule = CategorizationRules.firstMatch(in: rules, kind: kind, description: description, note: note)
            category = rule?.categoryID ?? TransactionCategory.otherID(for: kind)
            tags = rule?.tags ?? []
        }
        return Transaction(
            date: date,
            status: value("status", in: row).flatMap(TransactionStatus.init(rawValue:)) ?? .confirmed,
            description: description,
            kind: kind,
            categoryID: category,
            amount: amount,
            currency: currency,
            accountID: account.id,
            cardID: card?.id,
            destinationAccountID: kind == .transfer ? destination?.id : nil,
            actualDebitedPrincipal: debited,
            exchangeRate: rate(value("rate", in: row)),
            isShared: value("shared", in: row)?.lowercased() == "yes",
            note: note,
            tags: tags,
        )
    }

    /// The account whose bank and name, or just name, match ("Bank One Savings", "Cash").
    private func account(named name: String) -> Account? {
        let wanted = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return records.accounts.first { account in
            let full = [account.bank, account.name].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
            return [full, account.name].contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == wanted }
        }
    }

    /// By id or stored name; `nil` when the row has none or one this app doesn't know, which a
    /// rule or else "Other" of the right kind then fills.
    private func categoryID(_ text: String?, kind: TransactionKind) -> String? {
        guard let text else { return nil }
        return records.categories.first { category in
            category.kind == kind && (category.id == text || category.name.localizedCaseInsensitiveCompare(text) == .orderedSame)
        }?.id
    }

    /// The rate the file recorded, or today's when it has none.
    private func rate(_ text: String?) -> ExchangeRate {
        guard let second = currencies.second,
              let text,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              let rate = try? ExchangeRate(principal: currencies.principal, second: second, rate: value)
        else { return currencies.exchangeRate }
        return rate
    }

    /// "2026-10-22", read as that day in the person's calendar, at noon so time zones can't move it.
    private func day(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

/// What makes two movements the same for de-duplication.
private struct Fingerprint: Hashable {
    let day: String
    let amount: Decimal
    let currency: String
    let accountID: UUID
    let kind: TransactionKind
    let description: String

    init(_ transaction: Transaction) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: transaction.date)
        day = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        amount = transaction.amount
        currency = transaction.currency
        accountID = transaction.accountID
        kind = transaction.kind
        description = transaction.description
    }
}

/// RFC 4180 reading: quoted fields may hold commas, doubled quotes and line breaks.
enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var characters = text.makeIterator()
        var pending: Character?
        while let character = pending ?? characters.next() {
            pending = nil
            if isQuoted {
                if character == "\"" {
                    let next = characters.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        isQuoted = false
                        pending = next
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": isQuoted = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
