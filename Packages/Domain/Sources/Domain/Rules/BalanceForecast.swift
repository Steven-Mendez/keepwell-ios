import Foundation

/// "At the end of the month you'll have about C$X": the money in bank and cash accounts today,
/// moved by what is already planned for the rest of the month and by the usual spending of the days
/// left. Every figure is in the principal currency. The web app computes it line by line the same.
public struct BalanceForecast: Hashable, Sendable {
    /// How many complete months before the current one the usual spending averages.
    public static let usualSpendingMonths = 3

    public let currency: String
    /// Balances of deposit and cash accounts today, at the settings rate.
    public let availableToday: Decimal
    /// Drafts from today through month end on bank and cash accounts.
    public let draftIncome: Decimal
    public let draftExpenses: Decimal
    /// Occurrences of active rules not recorded yet, through month end, paid from bank or cash.
    public let recurringIncome: Decimal
    public let recurringExpenses: Decimal
    /// What credit cards due this month ask for (`CardStatement.amountDue`).
    public let cardPayments: Decimal
    /// The average monthly day-to-day spending, for the days left after today.
    public let usualSpending: Decimal

    public init(
        currency: String,
        availableToday: Decimal,
        draftIncome: Decimal,
        draftExpenses: Decimal,
        recurringIncome: Decimal,
        recurringExpenses: Decimal,
        cardPayments: Decimal,
        usualSpending: Decimal,
    ) {
        self.currency = currency
        self.availableToday = availableToday
        self.draftIncome = draftIncome
        self.draftExpenses = draftExpenses
        self.recurringIncome = recurringIncome
        self.recurringExpenses = recurringExpenses
        self.cardPayments = cardPayments
        self.usualSpending = usualSpending
    }

    /// Drafts and recurring income still to come.
    public var plannedIncome: Decimal {
        draftIncome + recurringIncome
    }

    /// Drafts and recurring expenses still to come.
    public var plannedExpenses: Decimal {
        draftExpenses + recurringExpenses
    }

    /// The month-end estimate.
    public var total: Decimal {
        availableToday + plannedIncome - plannedExpenses - cardPayments - usualSpending
    }

    /// - Second-currency amounts convert at today's settings rate, as net worth does; past spending
    ///   keeps each movement's own principal amount, as the summary does.
    /// - Transfers move money between the person's accounts and are left out; card purchases are
    ///   paid through `cardPayments` instead of on their own.
    /// - Usual spending averages confirmed expenses on bank and cash accounts not recorded by a
    ///   rule (rules are already counted) over the last `usualSpendingMonths` complete months that
    ///   had any, times the days after today over the days in the month.
    public init(
        accounts: [Account],
        transactions: [Transaction],
        rules: [RecurringRule],
        settings: CurrencySettings,
        now: Date,
        calendar: Calendar,
    ) {
        let period = Period(accounts: accounts, settings: settings, now: now, calendar: calendar)
        let available = accounts.filter { $0.kind != .credit }
            .flatMap { Balances.balance(of: $0, transactions: transactions, calendar: calendar) }
            .reduce(Decimal(0)) { $0 + period.principal($1.amount, $1.currency) }
        let drafts = Self.drafts(transactions, period)
        let recurring = Self.recurring(rules, period)
        let cardPayments = accounts.reduce(Decimal(0)) { total, account in
            guard account.kind == .credit,
                  let dueDay = account.creditTerms?.dueDay,
                  let due = BillingCycle.nextOccurrence(ofDay: dueDay, onOrAfter: now, calendar: calendar),
                  due < period.end
            else { return total }
            return total + CardStatement.amountDue(
                on: due,
                account: account,
                transactions: transactions,
                settings: settings,
                calendar: calendar,
            )
        }
        let average = Self.averageUsualSpending(
            transactions.filter { $0.recurringID == nil && period.isSpendable($0.accountID) },
            before: period.month,
            calendar: calendar,
        )
        self.init(
            currency: settings.principal,
            availableToday: available,
            draftIncome: drafts.income,
            draftExpenses: drafts.expenses,
            recurringIncome: recurring.income,
            recurringExpenses: recurring.expenses,
            cardPayments: cardPayments,
            usualSpending: average * Decimal(period.daysLeft) / Decimal(period.daysInMonth),
        )
    }

    /// The rest of the current month and how amounts reach the principal currency.
    private struct Period {
        let month: YearMonth
        let today: Date
        /// Start of the next month.
        let end: Date
        let lastDay: Date
        let daysInMonth: Int
        /// Days after today until the month ends.
        let daysLeft: Int
        let calendar: Calendar
        private let settings: CurrencySettings
        private let kinds: [UUID: AccountKind]

        init(accounts: [Account], settings: CurrencySettings, now: Date, calendar: Calendar) {
            today = calendar.startOfDay(for: now)
            month = YearMonth(containing: now, calendar: calendar)
            end = month.dateInterval(in: calendar)?.end ?? today
            lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? today
            daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count ?? 30
            daysLeft = daysInMonth - calendar.component(.day, from: today)
            self.calendar = calendar
            self.settings = settings
            kinds = Dictionary(accounts.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        }

        /// At today's settings rate; a currency the settings no longer convert counts as nothing.
        func principal(_ amount: Decimal, _ currency: String) -> Decimal {
            (try? settings.exchangeRate.convert(Money(amount, currency), to: settings.principal).amount) ?? 0
        }

        /// Bank and cash accounts; card purchases are paid through the card payment.
        func isSpendable(_ accountID: UUID) -> Bool {
            kinds[accountID].map { $0 != .credit } ?? false
        }
    }

    private static func drafts(_ transactions: [Transaction], _ period: Period) -> (income: Decimal, expenses: Decimal) {
        var income = Decimal(0)
        var expenses = Decimal(0)
        for transaction in transactions
            where !transaction.isConfirmed && transaction.date >= period.today && transaction.date < period.end
            && period.isSpendable(transaction.accountID)
        {
            let amount = period.principal(transaction.amount, transaction.currency)
            switch transaction.kind {
            case .income: income += amount
            case .expense: expenses += amount
            case .transfer: continue
            }
        }
        return (income, expenses)
    }

    private static func recurring(_ rules: [RecurringRule], _ period: Period) -> (income: Decimal, expenses: Decimal) {
        var income = Decimal(0)
        var expenses = Decimal(0)
        for rule in rules where rule.kind != .transfer && period.isSpendable(rule.accountID) {
            let count = RecurringSchedule.pending(rule, through: period.lastDay, calendar: period.calendar).count
            let amount = period.principal(rule.amount, rule.currency) * Decimal(count)
            if rule.kind == .income {
                income += amount
            } else {
                expenses += amount
            }
        }
        return (income, expenses)
    }

    /// Average confirmed spending of the complete months before `month` that had any, so a month
    /// before the person started doesn't drag it down. Zero without any.
    static func averageUsualSpending(_ transactions: [Transaction], before month: YearMonth, calendar: Calendar) -> Decimal {
        let totals = SpendingHistory.monthlyExpenses(
            endingAt: month.adding(months: -1),
            count: usualSpendingMonths,
            transactions: transactions,
            calendar: calendar,
        )
        .map(\.expense)
        .filter { $0 > 0 }
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Decimal(totals.count)
    }
}
