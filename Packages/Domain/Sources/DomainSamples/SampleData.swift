import Domain
import Foundation

/// A small, fictional data set (generic banks, made-up amounts and card digits) shaped like the
/// design: two deposit accounts, cash, a dual-currency credit card and a
/// single-currency card, plus a month of movements. Dates are relative to `referenceDate` so
/// previews and snapshots stay deterministic.
public struct SampleData: Sendable {
    public let settings: Settings
    public let accounts: [Account]
    public let cards: [Card]
    public let transactions: [Transaction]
    public let categories: [TransactionCategory]
    public let recurringRules: [RecurringRule]
    public let savingsGoals: [SavingsGoal]

    public enum IDs {
        public static let savings = UUID(uuidString: "00000000-0000-0000-0000-00000000A001") ?? UUID()
        public static let payroll = UUID(uuidString: "00000000-0000-0000-0000-00000000A002") ?? UUID()
        public static let cash = UUID(uuidString: "00000000-0000-0000-0000-00000000A003") ?? UUID()
        public static let mastercard = UUID(uuidString: "00000000-0000-0000-0000-00000000A004") ?? UUID()
        public static let visa = UUID(uuidString: "00000000-0000-0000-0000-00000000A005") ?? UUID()
        public static let savingsDebit = UUID(uuidString: "00000000-0000-0000-0000-00000000C001") ?? UUID()
        public static let savingsTransfer = UUID(uuidString: "00000000-0000-0000-0000-00000000C002") ?? UUID()
        public static let payrollDebit = UUID(uuidString: "00000000-0000-0000-0000-00000000C003") ?? UUID()
        public static let payrollTransfer = UUID(uuidString: "00000000-0000-0000-0000-00000000C004") ?? UUID()
        public static let mastercardHolder = UUID(uuidString: "00000000-0000-0000-0000-00000000C005") ?? UUID()
        public static let visaHolder = UUID(uuidString: "00000000-0000-0000-0000-00000000C007") ?? UUID()
        public static let streamingRule = UUID(uuidString: "00000000-0000-0000-0000-00000000D001") ?? UUID()
        public static let rentRule = UUID(uuidString: "00000000-0000-0000-0000-00000000D002") ?? UUID()
        public static let salaryRule = UUID(uuidString: "00000000-0000-0000-0000-00000000D003") ?? UUID()
        public static let cashRule = UUID(uuidString: "00000000-0000-0000-0000-00000000D004") ?? UUID()
        public static let tripGoal = UUID(uuidString: "00000000-0000-0000-0000-00000000E001") ?? UUID()
        public static let emergencyGoal = UUID(uuidString: "00000000-0000-0000-0000-00000000E002") ?? UUID()
        public static let phoneGoal = UUID(uuidString: "00000000-0000-0000-0000-00000000E003") ?? UUID()
    }

    /// The sample's fixed "today": 22 October 2026.
    public static let defaultReferenceDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18)) ?? .now
    }()

    public static let standard = Self(referenceDate: defaultReferenceDate)

    public init(referenceDate: Date, calendar: Calendar = .current) {
        let rateValue = Decimal(string: "36.6243") ?? 1
        let currencies = (try? CurrencySettings(principal: "USD", second: "NIO", rate: rateValue)) ?? Self.fallbackCurrencies
        settings = Settings(currencies: currencies, hasCompletedOnboarding: true)
        let rate = currencies.exchangeRate
        categories = TransactionCategory.defaults

        let month = YearMonth(containing: referenceDate, calendar: calendar)
        let monthStart = month.dateInterval(in: calendar)?.start ?? referenceDate
        let opening = month.adding(months: -2).dateInterval(in: calendar)?.start ?? referenceDate
        func day(_ number: Int, monthOffset: Int = 0) -> Date {
            let start = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) ?? monthStart
            return calendar.date(byAdding: DateComponents(day: number - 1, hour: 12), to: start) ?? start
        }

        accounts = Self.makeAccounts(opening: opening)
        cards = Self.makeCards()
        transactions = Self.makeTransactions(rate: rate, day: day)
        recurringRules = Self.makeRecurringRules(day: day)
        savingsGoals = Self.makeSavingsGoals(month: month)
    }

    /// A trip due in two months, an emergency fund without a date and a phone already paid for.
    static func makeSavingsGoals(month: YearMonth) -> [SavingsGoal] {
        [
            SavingsGoal(
                id: IDs.tripGoal, name: "Trip", target: Money(15000, "NIO"), saved: 4500,
                targetMonth: try? TargetMonth(month.adding(months: 2)), icon: "airplane", color: "blue",
            ),
            SavingsGoal(
                id: IDs.emergencyGoal, name: "Emergency fund", target: Money(3000, "USD"), saved: 1200,
                icon: "umbrella", color: "green",
            ),
            SavingsGoal(
                id: IDs.phoneGoal, name: "New phone", target: Money(800, "USD"), saved: 800, icon: "phone", color: "purple",
            ),
        ]
    }

    /// A subscription on the credit card, rent and a weekly cash top-up from savings, and the salary.
    static func makeRecurringRules(day: (Int, Int) -> Date) -> [RecurringRule] {
        [
            RecurringRule(
                id: IDs.streamingRule, name: "Streaming", kind: .expense, categoryID: "subscriptions",
                amount: Decimal(string: "15.99") ?? 0, currency: "USD", accountID: IDs.mastercard, cardID: IDs.mastercardHolder,
                frequency: .monthly, startDate: day(23, -2), nextDate: day(23, 0), isSubscription: true, autoConfirm: true,
            ),
            RecurringRule(
                id: IDs.rentRule, name: "Rent", kind: .expense, categoryID: "housing",
                amount: 18000, currency: "NIO", accountID: IDs.savings, cardID: IDs.savingsTransfer,
                frequency: .monthly, startDate: day(1, -2), nextDate: day(1, 1),
            ),
            RecurringRule(
                id: IDs.cashRule, name: "Cash for the week", kind: .transfer, categoryID: nil,
                amount: 1000, currency: "NIO", accountID: IDs.savings, cardID: IDs.savingsTransfer,
                destinationAccountID: IDs.cash, frequency: .weekly, interval: 2, startDate: day(10, 0), nextDate: day(24, 0),
            ),
            RecurringRule(
                id: IDs.salaryRule, name: "Salary", kind: .income, categoryID: "salary",
                amount: 1500, currency: "USD", accountID: IDs.payroll, cardID: IDs.payrollTransfer,
                frequency: .monthly, startDate: day(30, -2), nextDate: day(30, 0), autoConfirm: true, isPaused: true,
            ),
        ]
    }
}
