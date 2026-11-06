import Foundation

/// The backup file shared by the iOS and web apps: the whole store, deleted records included.
///
/// Portable on purpose: every decimal is an exact string ("36.6243", never a JSON number, which
/// JavaScript would read as a binary double), ids are lowercase UUIDs as `crypto.randomUUID()`
/// writes them, and dates are ISO 8601 with milliseconds, as `Date.toISOString()` writes them.
/// Optional fields are left out when empty. A deleted record carries `deletedAt`; a default
/// category absent from the file is simply not deleted.
public struct BackupSnapshot: Codable, Sendable, Equatable {
    /// Raised on a breaking change, so an older app refuses a file it doesn't understand.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let exportedAt: Date
    public let settings: SettingsBackup
    public let accounts: [AccountBackup]
    public let cards: [CardBackup]
    public let categories: [CategoryBackup]
    public let transactions: [TransactionBackup]

    /// `nil` when there are no settings yet: before onboarding there is nothing to back up.
    public init?(contents: BackupContents, exportedAt: Date) {
        guard let settings = contents.settings else { return nil }
        schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.settings = SettingsBackup(settings)
        accounts = contents.accounts.map(AccountBackup.init)
        cards = contents.cards.map(CardBackup.init)
        categories = contents.categories.enumerated().map { CategoryBackup($0.element, sortIndex: $0.offset) }
        transactions = contents.transactions.map(TransactionBackup.init)
    }

    /// Converts and validates every record, so a damaged file fails here, before anything is replaced.
    public func contents() throws(DomainError) -> BackupContents {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw .corruptedData("Backup schema \(schemaVersion) is newer than this app")
        }
        var accounts: [Stamped<Account>] = []
        for row in self.accounts {
            try accounts.append(row.toDomain())
        }
        var cards: [Stamped<Card>] = []
        for row in self.cards {
            try cards.append(row.toDomain())
        }
        var categories: [Stamped<TransactionCategory>] = []
        for row in self.categories.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            categories.append(row.toDomain())
        }
        var transactions: [Stamped<Transaction>] = []
        for row in self.transactions {
            try transactions.append(row.toDomain())
        }
        return try BackupContents(
            settings: settings.toDomain(),
            accounts: accounts,
            cards: cards,
            categories: categories,
            transactions: transactions,
        )
    }

    public func encoded() throws(DomainError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(PortableDate.withMilliseconds))
        }
        do {
            return try encoder.encode(self)
        } catch {
            throw .persistence("Backup encoding: \(error)")
        }
    }

    public static func decode(_ data: Data) throws(DomainError) -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = PortableDate.parse(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Date \(text)"))
            }
            return date
        }
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw .corruptedData("Not a Keepwell backup: \(error)")
        }
    }
}

// MARK: - Records

public struct MoneyBackup: Codable, Sendable, Equatable {
    public let amount: String
    public let currency: String

    init(_ money: Money) {
        amount = PortableDecimal.string(money.amount)
        currency = money.currency
    }

    func toDomain() throws(DomainError) -> Money {
        try Money(PortableDecimal.decimal(amount), Money.normalizedCurrency(currency))
    }
}

public struct SettingsBackup: Codable, Sendable, Equatable {
    public struct Currencies: Codable, Sendable, Equatable {
        public let principal: String
        public let second: String?
        /// "1 principal = rate second".
        public let rate: String
    }

    public let currencies: Currencies
    public let unlockMethod: UnlockMethod
    public let relockAfterSeconds: TimeInterval
    public let hidesAmountsInAppSwitcher: Bool
    public let isICloudBackupEnabled: Bool
    public let paymentReminderDaysBefore: Int
    public let hasCompletedOnboarding: Bool
    public let updatedAt: Date

    init(_ stamped: Stamped<Settings>) {
        let settings = stamped.value
        currencies = Currencies(
            principal: settings.currencies.principal,
            second: settings.currencies.second,
            rate: PortableDecimal.string(settings.currencies.rate),
        )
        unlockMethod = settings.unlockMethod
        relockAfterSeconds = settings.relockAfter
        hidesAmountsInAppSwitcher = settings.hidesAmountsInAppSwitcher
        isICloudBackupEnabled = settings.isICloudBackupEnabled
        paymentReminderDaysBefore = settings.paymentReminderDaysBefore
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        updatedAt = stamped.metadata.updatedAt
    }

    func toDomain() throws(DomainError) -> Stamped<Settings> {
        let settings = try Settings(
            currencies: CurrencySettings(
                principal: Money.normalizedCurrency(currencies.principal),
                second: currencies.second.map { code throws(DomainError) in try Money.normalizedCurrency(code) },
                rate: PortableDecimal.decimal(currencies.rate),
            ),
            unlockMethod: unlockMethod,
            relockAfter: relockAfterSeconds,
            hidesAmountsInAppSwitcher: hidesAmountsInAppSwitcher,
            isICloudBackupEnabled: isICloudBackupEnabled,
            paymentReminderDaysBefore: paymentReminderDaysBefore,
            hasCompletedOnboarding: hasCompletedOnboarding,
        )
        return Stamped(settings, RecordMetadata(createdAt: updatedAt, updatedAt: updatedAt))
    }
}

public struct AccountBackup: Codable, Sendable, Equatable {
    public struct Terms: Codable, Sendable, Equatable {
        public let debtMode: DebtMode
        public let limit: MoneyBackup?
        public let cutoffDay: Int?
        public let dueDay: Int?
    }

    public let id: String
    public let name: String
    public let bank: String?
    public let kind: AccountKind
    public let openingBalances: [MoneyBackup]
    public let openingDate: Date
    public let creditTerms: Terms?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<Account>) {
        let account = stamped.value
        id = PortableID.string(account.id)
        name = account.name
        bank = account.bank
        kind = account.kind
        openingBalances = account.openingBalances.map(MoneyBackup.init)
        openingDate = account.openingDate
        creditTerms = account.creditTerms.map {
            Terms(debtMode: $0.debtMode, limit: $0.limit.map(MoneyBackup.init), cutoffDay: $0.cutoffDay, dueDay: $0.dueDay)
        }
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() throws(DomainError) -> Stamped<Account> {
        var balances: [Money] = []
        for balance in openingBalances {
            try balances.append(balance.toDomain())
        }
        let terms = try creditTerms.map { terms throws(DomainError) in
            try CreditTerms(
                debtMode: terms.debtMode,
                limit: terms.limit.map { limit throws(DomainError) in try limit.toDomain() },
                cutoffDay: terms.cutoffDay,
                dueDay: terms.dueDay,
            )
        }
        let account = try Account(
            id: PortableID.uuid(id),
            name: name,
            bank: bank,
            kind: kind,
            openingBalances: balances,
            openingDate: openingDate,
            creditTerms: terms,
        )
        return Stamped(account, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}

public struct CardBackup: Codable, Sendable, Equatable {
    public struct Expiry: Codable, Sendable, Equatable {
        public let month: Int
        public let year: Int
    }

    public let id: String
    public let accountId: String
    public let kind: CardKind
    public let network: CardNetwork?
    public let lastFour: String?
    public let color: CardColor?
    public let productName: String?
    public let expiry: Expiry?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<Card>) {
        let card = stamped.value
        id = PortableID.string(card.id)
        accountId = PortableID.string(card.accountID)
        kind = card.kind
        network = card.network
        lastFour = card.lastFour
        color = card.color
        productName = card.productName
        expiry = card.expiry.map { Expiry(month: $0.month, year: $0.year) }
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() throws(DomainError) -> Stamped<Card> {
        let card = try Card(
            id: PortableID.uuid(id),
            accountID: PortableID.uuid(accountId),
            kind: kind,
            network: network,
            lastFour: lastFour,
            color: color,
            productName: productName,
            expiry: expiry.map { expiry throws(DomainError) in try CardExpiry(month: expiry.month, year: expiry.year) },
        )
        return Stamped(card, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}

public struct CategoryBackup: Codable, Sendable, Equatable {
    /// A slug, not a UUID: defaults share theirs on every device ("groceries"), so two devices
    /// that seed them converge on one record; created ones are "custom-<uuid>".
    public let id: String
    public let name: String
    public let kind: TransactionKind
    public let icon: String?
    public let color: String?
    public let isRenamed: Bool
    public let sortIndex: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<TransactionCategory>, sortIndex: Int) {
        let category = stamped.value
        id = category.id
        name = category.name
        kind = category.kind
        icon = category.icon
        color = category.color
        isRenamed = category.isRenamed
        self.sortIndex = sortIndex
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() -> Stamped<TransactionCategory> {
        Stamped(
            TransactionCategory(id: id, name: name, kind: kind, icon: icon, color: color, isRenamed: isRenamed),
            RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt),
        )
    }
}

public struct TransactionBackup: Codable, Sendable, Equatable {
    public struct Rate: Codable, Sendable, Equatable {
        public let principal: String
        public let second: String
        /// "1 principal = rate second".
        public let rate: String
    }

    public let id: String
    public let date: Date
    public let status: TransactionStatus
    public let description: String
    public let kind: TransactionKind
    public let categoryId: String?
    /// Always positive; `kind` carries the direction.
    public let amount: String
    public let currency: String
    public let accountId: String
    public let cardId: String?
    public let destinationAccountId: String?
    public let actualDebitedPrincipal: String?
    public let exchangeRate: Rate
    public let isShared: Bool
    public let note: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<Transaction>) {
        let transaction = stamped.value
        id = PortableID.string(transaction.id)
        date = transaction.date
        status = transaction.status
        description = transaction.description
        kind = transaction.kind
        categoryId = transaction.categoryID
        amount = PortableDecimal.string(transaction.amount)
        currency = transaction.currency
        accountId = PortableID.string(transaction.accountID)
        cardId = transaction.cardID.map(PortableID.string)
        destinationAccountId = transaction.destinationAccountID.map(PortableID.string)
        actualDebitedPrincipal = transaction.actualDebitedPrincipal.map(PortableDecimal.string)
        exchangeRate = Rate(
            principal: transaction.exchangeRate.principal,
            second: transaction.exchangeRate.second,
            rate: PortableDecimal.string(transaction.exchangeRate.rate),
        )
        isShared = transaction.isShared
        note = transaction.note
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() throws(DomainError) -> Stamped<Transaction> {
        let amount = try PortableDecimal.decimal(amount)
        let debited = try actualDebitedPrincipal.map { value throws(DomainError) in try PortableDecimal.decimal(value) }
        try Transaction.checkAmounts(amount, actualDebitedPrincipal: debited)
        let transaction = try Transaction(
            id: PortableID.uuid(id),
            date: date,
            status: status,
            description: description,
            kind: kind,
            categoryID: categoryId,
            amount: amount,
            currency: Money.normalizedCurrency(currency),
            accountID: PortableID.uuid(accountId),
            cardID: cardId.map { id throws(DomainError) in try PortableID.uuid(id) },
            destinationAccountID: destinationAccountId.map { id throws(DomainError) in try PortableID.uuid(id) },
            actualDebitedPrincipal: debited,
            exchangeRate: ExchangeRate(
                principal: Money.normalizedCurrency(exchangeRate.principal),
                second: Money.normalizedCurrency(exchangeRate.second),
                rate: PortableDecimal.decimal(exchangeRate.rate),
            ),
            isShared: isShared,
            note: note,
        )
        return Stamped(transaction, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}

// MARK: - Portable scalars

/// Exact decimal text with a dot and no exponent or grouping, which both Swift and JavaScript
/// decimal libraries read without going through a binary double.
enum PortableDecimal {
    static func string(_ value: Decimal) -> String {
        value.description
    }

    static func decimal(_ text: String) throws(DomainError) -> Decimal {
        // `Decimal(string:)` alone accepts "12abc" as 12, so the shape is checked first.
        guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { throw .corruptedData("Invalid decimal '\(text)'") }
        return value
    }
}

/// Lowercase, as the web writes them, so the same id is the same string on both platforms.
enum PortableID {
    static func string(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func uuid(_ text: String) throws(DomainError) -> UUID {
        guard let id = UUID(uuidString: text) else { throw .corruptedData("Invalid id '\(text)'") }
        return id
    }
}

enum PortableDate {
    static let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    /// Accepts both forms: JavaScript always writes milliseconds, older Swift writers never do.
    static func parse(_ text: String) -> Date? {
        (try? withMilliseconds.parse(text)) ?? (try? wholeSeconds.parse(text))
    }
}
