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
    }
}
