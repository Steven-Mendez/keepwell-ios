import Domain
import Foundation

public protocol GetTransactionContextUseCase: Sendable {
    func execute() async throws(DomainError) -> TransactionContext
}

public struct DefaultGetTransactionContextUseCase: GetTransactionContextUseCase {
    private let settings: any SettingsRepository
    private let categories: any CategoryRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    let transactions: any TransactionRepository
    private let rules: (any CategorizationRuleRepository)?
    private let merchants: (any MerchantRepository)?
    let personalDebts: (any PersonalDebtRepository)?
    let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Without `rules`, no category comes from a rule; without `merchants`, the context names none
    /// and a movement's links are kept as they come. With `personalDebts`, a stored movement's
    /// receipt counts the person's part of split expenses in its category total.
    public init(
        settings: any SettingsRepository,
        categories: any CategoryRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        transactions: any TransactionRepository,
        rules: (any CategorizationRuleRepository)? = nil,
        merchants: (any MerchantRepository)? = nil,
        personalDebts: (any PersonalDebtRepository)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.settings = settings
        self.categories = categories
        self.accounts = accounts
        self.cards = cards
        self.transactions = transactions
        self.rules = rules
        self.merchants = merchants
        self.personalDebts = personalDebts
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> TransactionContext {
        try await context(of: transactions.fetchTransactions(in: nil))
    }

    /// `excluding` leaves one movement out of the balances (the one being edited), so its old
    /// version doesn't count next to the new one. `currencies` replaces the settings' (an edit
    /// keeps the rate it was recorded with), and `usesRules` is off for edits: rules only choose
    /// the category of a movement being logged.
    func context(
        of movements: [Transaction],
        excluding excluded: UUID? = nil,
        currencies override: CurrencySettings? = nil,
        usesRules: Bool = true,
    ) async throws(DomainError) -> TransactionContext {
        let settingsCurrencies = try await settings.load()?.currencies ?? .fallbackForMovements
        let currencies = override ?? settingsCurrencies
        let allAccounts = try await accounts.fetchAccounts()
        let allCards = try await cards.fetchCards()
        let counted = movements.filter { $0.id != excluded }

        var balances: [UUID: [Money]] = [:]
        for account in allAccounts {
            balances[account.id] = Balances.balance(of: account, transactions: counted, calendar: calendar)
        }
        var lastUsed: [PaymentSource: Date] = [:]
        var categoryUsage: [String: Int] = [:]
        for movement in movements {
            let source = movement.cardID.map(PaymentSource.card) ?? .account(movement.accountID)
            lastUsed[source] = max(lastUsed[source] ?? .distantPast, movement.date)
            if let category = movement.categoryID {
                categoryUsage[category, default: 0] += 1
            }
        }
        return try await TransactionContext(
            currencies: currencies,
            categories: categories.fetchCategories(),
            accounts: allAccounts,
            cards: allCards,
            balances: balances,
            lastUsed: lastUsed,
            categoryUsage: categoryUsage,
            tagUsage: Tags.usage(in: movements),
            rules: usesRules ? rules?.fetchCategorizationRules() ?? [] : [],
            merchants: merchants?.fetchMerchants(),
        )
    }

    /// The principal currency in settings now, which month totals are reported in.
    func principalCurrency() async throws(DomainError) -> String {
        try await (settings.load()?.currencies ?? .fallbackForMovements).principal
    }
}

public protocol SaveTransactionUseCase: Sendable {
    func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction
}

public struct DefaultSaveTransactionUseCase: SaveTransactionUseCase {
    private let context: any GetTransactionContextUseCase
    private let transactions: any TransactionRepository
    private let recurringRules: (any RecurringRuleRepository)?
    private let materialize: (any MaterializeRecurringUseCase)?
    private let merchants: (any MerchantRepository)?
    private let personalDebts: (any PersonalDebtRepository)?
    private let calendar: Calendar
    private let makeID: @Sendable () -> UUID

    /// Without `recurringRules`, "Repeat" is ignored and only the movement is saved. Without
    /// `merchants`, a merchant the draft picked new (`MerchantLink.new`) isn't created. With
    /// `personalDebts`, the receipt's category total counts the person's part of split expenses.
    public init(
        context: any GetTransactionContextUseCase,
        transactions: any TransactionRepository,
        recurringRules: (any RecurringRuleRepository)? = nil,
        materialize: (any MaterializeRecurringUseCase)? = nil,
        merchants: (any MerchantRepository)? = nil,
        personalDebts: (any PersonalDebtRepository)? = nil,
        calendar: Calendar = .current,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        self.context = context
        self.transactions = transactions
        self.recurringRules = recurringRules
        self.materialize = materialize
        self.merchants = merchants
        self.personalDebts = personalDebts
        self.calendar = calendar
        self.makeID = makeID
    }

    public func execute(_ draft: TransactionDraft) async throws(DomainError) -> SavedTransaction {
        var current = try await context.execute()
        var draft = draft
        if recurringRules == nil {
            draft.repeatFrequency = nil
        }
        let created = try Self.creatingMerchants(&draft, context: &current, canCreate: merchants != nil, makeID: makeID)
        let transaction = try Self.validated(draft, context: current)
        let rule = try draft.repeatFrequency.map { frequency throws(DomainError) in
            try Self.rule(repeating: transaction, every: frequency, id: draft.recurringRuleID, calendar: calendar)
        }
        if let merchants, !created.isEmpty {
            // The new merchants, the movement and its rule in one save: a save that fails leaves no
            // merchant behind.
            try await merchants.commit(MerchantChanges(
                transactions: [transaction],
                recurringRules: recurringRules == nil ? [] : rule.map { [$0] } ?? [],
                savedMerchants: created,
            ))
        } else {
            try await transactions.save(transaction)
            if let rule, let recurringRules {
                try await recurringRules.save(rule)
            }
        }
        if rule != nil, recurringRules != nil {
            try await materialize?.execute()
        }

        return try await Self.receipt(
            of: transaction,
            accounts: current.accounts,
            movements: transactions.fetchTransactions(in: nil),
            principal: current.currencies.principal,
            calendar: calendar,
            debts: personalDebts?.fetchPersonalDebts() ?? [],
        )
    }

    /// Resolves the draft's `new` merchant links: the equivalent merchant already saved, else a new
    /// one returned for saving with the movement. A transfer names none, so it creates none; without
    /// a merchant store (`canCreate` off) a new one is left out.
    static func creatingMerchants(
        _ draft: inout TransactionDraft,
        context: inout TransactionContext,
        canCreate: Bool,
        makeID: () -> UUID,
    ) throws(DomainError) -> [Merchant] {
        func isNew(_ link: MerchantLink) -> Bool {
            if case .new = link {
                return true
            }
            return false
        }
        guard isNew(draft.merchant) || isNew(draft.via) else { return [] }
        guard draft.kind != .transfer, canCreate else {
            draft.merchant = isNew(draft.merchant) ? .unlinked : draft.merchant
            draft.via = isNew(draft.via) ? .unlinked : draft.via
            return []
        }
        let resolved = try Merchants.creatingNew(
            [draft.merchant, draft.via],
            in: context.merchants ?? [],
            categories: context.categories,
            makeID: makeID,
        )
        draft.merchant = resolved.links[0]
        draft.via = resolved.links[1]
        context = context.adding(merchants: resolved.created)
        return resolved.created
    }

    /// What the receipt states about a stored movement: its account's balances with every movement
    /// and, for an expense, its category's spending that month (the person's part of split expenses,
    /// as the summary counts it with `debts`). Also rebuilds a receipt from history.
    static func receipt(
        of transaction: Transaction,
        accounts: [Account],
        movements: [Transaction],
        principal: String,
        calendar: Calendar,
        debts: [PersonalDebt] = [],
    ) throws(DomainError) -> SavedTransaction {
        guard let account = accounts.first(where: { $0.id == transaction.accountID }) else { throw .notFound(transaction.accountID) }
        let newBalances = Balances.balance(of: account, transactions: movements, calendar: calendar)
        var categoryTotal: Money?
        if transaction.kind == .expense {
            let month = YearMonth(containing: transaction.date, calendar: calendar)
            let summary = MonthlySummary(
                month: month, transactions: movements, currency: principal, calendar: calendar, debts: DebtLinks(debts),
            )
            let total = summary.categories.first { $0.categoryID == transaction.categoryID }?.amount ?? 0
            categoryTotal = Money(total, principal)
        }
        return SavedTransaction(transaction: transaction, account: account, newBalances: newBalances, categoryMonthTotal: categoryTotal)
    }

    /// Checks a draft and builds the movement to store. With `existing` it edits that movement: it
    /// keeps the rate it was recorded with (so its currencies are the allowed ones), whether it's
    /// shared and the recurring rule behind it.
    static func validated(
        _ draft: TransactionDraft,
        context: TransactionContext,
        existing: Transaction? = nil,
    ) throws(DomainError) -> Transaction {
        try Transaction.checkAmounts(draft.amount, actualDebitedPrincipal: draft.actualDebitedPrincipal)
        // The rate in force now travels with a new movement, so later rate edits don't rewrite it.
        let rate = existing?.exchangeRate ?? context.currencies.exchangeRate
        guard draft.currency == rate.principal || draft.currency == rate.second else {
            throw .invalidCurrency(draft.currency)
        }
        guard let source = draft.source, let accountID = context.accountID(for: source) else {
            throw .notFound(UUID(uuid: UUID_NULL))
        }

        // A new expense or income without a category goes through the rules first; when none
        // matches it takes its merchant's default category, else goes to "Other".
        let chosen = draft.kind == .transfer || draft.categoryID != nil || existing != nil
            ? draft.categoryID : TransactionCategory.otherID(for: draft.kind)
        if draft.kind == .transfer {
            try Transaction.checkDestination(draft.destinationAccountID, from: accountID, accounts: context.accounts)
        } else {
            try Transaction.checkCategory(chosen, kind: draft.kind, categories: context.categories)
        }

        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a new movement takes a rule, read from the text as typed (before the safety net).
        let rule = existing == nil
            ? CategorizationRules.categorizing(
                kind: draft.kind, categoryID: chosen, description: description, note: note, in: context.rules,
            )
            : nil
        let merchant = merchantFields(of: draft, context: context, existing: existing, rule: rule)
        let categoryID = draft.kind == .transfer ? nil : rule?.categoryID ?? merchant.defaultCategoryID ?? chosen
        let category = context.categories.first { $0.id == categoryID }
        let transaction = Transaction(
            id: draft.id,
            date: draft.date,
            status: draft.isDraft ? .planned : .confirmed,
            // Safety net only: the view model fills a localized description before saving.
            description: description.isEmpty ? (category?.name ?? "Transfer") : description,
            kind: draft.kind,
            categoryID: categoryID,
            amount: draft.amount,
            currency: draft.currency,
            accountID: accountID,
            cardID: source.cardID,
            destinationAccountID: draft.kind == .transfer ? draft.destinationAccountID : nil,
            actualDebitedPrincipal: draft.applicableDebit(principal: rate.principal, accountID: accountID),
            exchangeRate: rate,
            isShared: existing?.isShared ?? false,
            note: note.isEmpty ? nil : note,
            recurringID: existing?.recurringID ?? (draft.repeatFrequency == nil ? nil : draft.recurringRuleID),
            tags: rule.map { Tags.merging(draft.tags, with: $0.tags) } ?? draft.tags,
            merchantID: merchant.merchantID,
            viaMerchantID: merchant.viaMerchantID,
        )
        try Transaction.checkClosedAccounts(transaction, existing: existing, accounts: context.accounts)
        return transaction
    }

    /// The merchant links a movement saves and the default category its merchant brings. A transfer
    /// is between the person's own accounts: it names no business or platform, and turning an
    /// expense or income into one drops the links it had. A rule's merchant applies only when the
    /// movement names none, the person didn't clear the business on purpose and it is a live one;
    /// the merchant's default category only for a new movement without a category no rule matched.
    private static func merchantFields(
        of draft: TransactionDraft,
        context: TransactionContext,
        existing: Transaction?,
        rule: CategorizationRule?,
    ) -> (merchantID: UUID?, viaMerchantID: UUID?, defaultCategoryID: String?) {
        guard draft.kind != .transfer else { return (nil, nil, nil) }
        let links = Merchants.links(
            merchant: draft.merchant,
            via: draft.via,
            known: context.merchants,
            existing: existing.map { ($0.merchantID, $0.viaMerchantID) },
        )
        let ruleMerchant = rule?.merchantID.flatMap { id in
            draft.merchant != .unlinked && context.merchants?.contains { $0.id == id } == true ? id : nil
        }
        let merchantID = links.merchantID ?? ruleMerchant
        let defaultCategory = existing == nil && draft.categoryID == nil && rule == nil
            ? Merchants.category(of: context.merchant(links.merchantID), kind: draft.kind, categories: context.categories)
            : nil
        return (merchantID, links.viaMerchantID == merchantID ? nil : links.viaMerchantID, defaultCategory)
    }

    /// The rule "Repeat" saves: the movement as its first occurrence, the next one still ahead,
    /// waiting as drafts. A movement in "Subscriptions" makes it a subscription.
    static func rule(
        repeating transaction: Transaction,
        every frequency: RecurringFrequency,
        id: UUID,
        calendar: Calendar,
    ) throws(DomainError) -> RecurringRule {
        let first = RecurringRule(
            id: id,
            name: transaction.description,
            kind: transaction.kind,
            categoryID: transaction.categoryID,
            amount: transaction.amount,
            currency: transaction.currency,
            accountID: transaction.accountID,
            cardID: transaction.cardID,
            destinationAccountID: transaction.destinationAccountID,
            frequency: frequency,
            startDate: transaction.date,
            isSubscription: transaction.kind == .expense && transaction.categoryID == Subscriptions.categoryID,
            autoConfirm: false,
            note: transaction.note,
            tags: transaction.tags,
            merchantID: transaction.merchantID,
            viaMerchantID: transaction.viaMerchantID,
        )
        try first.checkSchedule(calendar: calendar)
        let next = RecurringSchedule.firstOccurrence(of: first, after: transaction.date, calendar: calendar) ?? transaction.date
        return first.with(nextDate: next)
    }
}

/// A movement checked and built exactly as saving builds it, without storing it, for callers that
/// store it in one write together with something else (a loan installment and the loan).
public protocol PrepareTransactionUseCase: Sendable {
    func execute(_ draft: TransactionDraft) async throws(DomainError) -> Transaction
}

public struct DefaultPrepareTransactionUseCase: PrepareTransactionUseCase {
    private let context: any GetTransactionContextUseCase

    public init(context: any GetTransactionContextUseCase) {
        self.context = context
    }

    public func execute(_ draft: TransactionDraft) async throws(DomainError) -> Transaction {
        var draft = draft
        draft.repeatFrequency = nil
        return try await DefaultSaveTransactionUseCase.validated(draft, context: context.execute())
    }
}

extension CurrencySettings {
    static let fallbackForMovements: CurrencySettings = {
        guard let settings = try? CurrencySettings() else { preconditionFailure("Default currency settings are valid") }
        return settings
    }()
}
