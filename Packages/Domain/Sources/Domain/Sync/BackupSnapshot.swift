import Foundation

/// The backup file shared by the iOS and web apps: the whole store, deleted records included.
///
/// Portable on purpose: every decimal is an exact string ("36.6243", never a JSON number, which
/// JavaScript would read as a binary double), ids are lowercase UUIDs as `crypto.randomUUID()`
/// writes them, and dates are ISO 8601 with milliseconds, as `Date.toISOString()` writes them.
/// Optional fields are left out when empty. A deleted record carries `deletedAt`; a default
/// category absent from the file is simply not deleted.
///
/// Version 2 added `recurringRules` and each movement's `recurringId`. A version 1 file has
/// neither and still restores, with no rules. A category's optional `monthlyBudget` came later
/// within version 2: it is additive, so older files restore without budgets and older apps skip it.
/// Version 3 added `savingsGoals`; versions 1 and 2 still restore, with no goals.
/// Version 4 added `loans` and `personalDebts`, `categorizationRules`, and the optional `tags` of a
/// movement and of a recurring rule; versions 1 to 3 still restore, with none of them.
public struct BackupSnapshot: Codable, Sendable, Equatable {
    /// Raised on a breaking change, so an older app refuses a file it doesn't understand.
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let exportedAt: Date
    public let settings: SettingsBackup
    public let accounts: [AccountBackup]
    public let cards: [CardBackup]
    public let categories: [CategoryBackup]
    public let transactions: [TransactionBackup]
    public let recurringRules: [RecurringRuleBackup]
    public let savingsGoals: [SavingsGoalBackup]
    public let loans: [LoanBackup]
    public let personalDebts: [PersonalDebtBackup]
    public let categorizationRules: [CategorizationRuleBackup]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case settings
        case accounts
        case cards
        case categories
        case transactions
        case recurringRules
        case savingsGoals
        case loans
        case personalDebts
        case categorizationRules
    }

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
        recurringRules = contents.recurringRules.map(RecurringRuleBackup.init)
        savingsGoals = contents.savingsGoals.map(SavingsGoalBackup.init)
        loans = contents.loans.map(LoanBackup.init)
        personalDebts = contents.personalDebts.map(PersonalDebtBackup.init)
        categorizationRules = contents.categorizationRules.enumerated().map {
            CategorizationRuleBackup($0.element, sortIndex: $0.offset)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(SettingsBackup.self, forKey: .settings)
        accounts = try container.decode([AccountBackup].self, forKey: .accounts)
        cards = try container.decode([CardBackup].self, forKey: .cards)
        categories = try container.decode([CategoryBackup].self, forKey: .categories)
        transactions = try container.decode([TransactionBackup].self, forKey: .transactions)
        // Version 1 files were written before recurring rules existed.
        recurringRules = try container.decodeIfPresent([RecurringRuleBackup].self, forKey: .recurringRules) ?? []
        // Versions 1 and 2 were written before savings goals existed.
        savingsGoals = try container.decodeIfPresent([SavingsGoalBackup].self, forKey: .savingsGoals) ?? []
        // Versions 1 to 3 were written before loans and personal debts existed.
        loans = try container.decodeIfPresent([LoanBackup].self, forKey: .loans) ?? []
        personalDebts = try container.decodeIfPresent([PersonalDebtBackup].self, forKey: .personalDebts) ?? []
        categorizationRules = try container.decodeIfPresent([CategorizationRuleBackup].self, forKey: .categorizationRules) ?? []
    }

    /// Converts and validates every record, so a damaged file fails here, before anything is replaced.
    public func contents() throws(DomainError) -> BackupContents {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw .corruptedData("Backup schema \(schemaVersion) is newer than this app")
        }
        return try BackupContents(
            settings: settings.toDomain(),
            accounts: accounts.stamped(),
            cards: cards.stamped(),
            categories: categories.sorted { $0.sortIndex < $1.sortIndex }.stamped(),
            transactions: transactions.stamped(),
            recurringRules: recurringRules.stamped(),
            savingsGoals: savingsGoals.stamped(),
            loans: loans.stamped(),
            personalDebts: personalDebts.stamped(),
            categorizationRules: categorizationRules.sorted { $0.sortIndex < $1.sortIndex }.stamped(),
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
    /// Left out when there is none, so files without budgets read exactly as before and an older
    /// app that doesn't know the key still opens the file.
    public let monthlyBudget: MoneyBackup?
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
        monthlyBudget = category.monthlyBudget.map(MoneyBackup.init)
        self.sortIndex = sortIndex
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    func toDomain() throws(DomainError) -> Stamped<TransactionCategory> {
        let budget = try monthlyBudget.map { budget throws(DomainError) in try budget.toDomain() }
        if let budget, budget.amount <= 0 {
            throw .invalidAmount
        }
        return Stamped(
            TransactionCategory(
                id: id,
                name: name,
                kind: kind,
                icon: icon,
                color: color,
                isRenamed: isRenamed,
                // The same rule as saving one: only expenses are budgeted.
                monthlyBudget: kind == .expense ? budget : nil,
            ),
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
    /// The recurring rule that recorded it (schema 2).
    public let recurringId: String?
    /// Normalized tags (schema 4), left out when there are none so older apps read the file as before.
    public let tags: [String]?
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
        recurringId = transaction.recurringID.map(PortableID.string)
        tags = transaction.tags.isEmpty ? nil : transaction.tags
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
            recurringID: recurringId.map { id throws(DomainError) in try PortableID.uuid(id) },
            tags: tags ?? [],
        )
        return Stamped(transaction, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}
