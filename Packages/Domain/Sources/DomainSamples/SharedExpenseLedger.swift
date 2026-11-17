import Domain
import Foundation

/// October 2026 in USD with shared expenses, the ledger keepwell-web's `shared-expenses.test.ts`
/// reads: groceries 100, a dinner of 90 split with Ana (30, repaid and deposited) and Luis (30),
/// 40 that Eva owes in full, salary 1000 and Ana's deposit of 30. The person spent 130 and earned
/// 1000; the movements add up to 230 and 1030.
public struct SharedExpenseLedger: Sendable {
    public let calendar: Calendar
    public let month: YearMonth
    /// A day after every movement, in the same month.
    public let now: Date
    public let account: Account
    public let groceries: Transaction
    public let shared: Transaction
    public let salary: Transaction
    public let deposit: Transaction
    public let movements: [Transaction]
    public let debts: [PersonalDebt]

    public var links: DebtLinks {
        DebtLinks(debts)
    }

    public init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Managua") ?? .gmt
        func day(_ day: Int, month: Int = 10) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .distantPast
        }
        let account = Account(name: "Bank", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: day(1, month: 9))
        func movement(_ kind: TransactionKind, _ amount: Decimal, _ category: String, _ date: Date, _ description: String) -> Transaction {
            Transaction(
                date: date, description: description, kind: kind, categoryID: category, amount: amount, currency: "USD",
                accountID: account.id, exchangeRate: .single("USD"),
            )
        }
        let groceries = movement(.expense, 100, "groceries", day(3), "Groceries")
        let shared = movement(.expense, 90, "restaurants", day(5), "Dinner")
        let paidByOthers = movement(.expense, 40, "leisure", day(6), "Concert")
        let salary = movement(.income, 1000, "salary", day(1), "Salary")
        let deposit = movement(.income, 30, "refunds", day(7), "Ana · Dinner")
        let ana = PersonalDebt(
            person: "Ana", direction: .theyOweMe, amount: Money(30, "USD"), date: shared.date,
            repayments: [DebtRepayment(amount: 30, date: deposit.date, transactionID: deposit.id)],
            settledAt: deposit.date, transactionID: shared.id,
        )
        let luis = PersonalDebt(
            person: "Luis",
            direction: .theyOweMe,
            amount: Money(30, "USD"),
            date: shared.date,
            transactionID: shared.id,
        )
        let eva = PersonalDebt(
            person: "Eva", direction: .theyOweMe, amount: Money(40, "USD"), date: paidByOthers.date, transactionID: paidByOthers.id,
        )
        self.calendar = calendar
        month = YearMonth(containing: day(5), calendar: calendar)
        now = day(20)
        self.account = account
        self.groceries = groceries
        self.shared = shared
        self.salary = salary
        self.deposit = deposit
        movements = [groceries, shared, paidByOthers, salary, deposit]
        debts = [ana, luis, eva]
    }
}
