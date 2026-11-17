import Foundation
import Testing
@testable import Domain

/// Shared expenses: a split movement counts only the person's part as spending, in every spending
/// view (summary, averages, budgets, forecast), never in balances; a repayment deposited into an
/// account changes the balance but is not income. Same cases as keepwell-web's
/// `tests/domain/shared-expenses.test.ts`.
@Suite("Shared expenses")
struct SharedExpensesTests {
    private let october = YearMonth(year: 2026, month: 10) ?? YearMonth(containing: .now, calendar: .current)

    private func owed(
        _ movement: Transaction,
        _ amount: String,
        person: String = "Ana",
        direction: DebtDirection = .theyOweMe,
        currency: String? = nil,
        repayments: [DebtRepayment] = [],
        settledAt: Date? = nil,
    ) -> PersonalDebt {
        PersonalDebt(
            person: person,
            direction: direction,
            amount: Money(Fixtures.decimal(amount), currency ?? movement.currency),
            date: movement.date,
            repayments: repayments,
            settledAt: settledAt,
            transactionID: movement.id,
        )
    }

    private var dinner: Transaction {
        Fixtures.transaction(amount: "900", currency: "NIO", category: "restaurants", rate: .single("NIO"))
    }

    // MARK: spendingAmount

    @Test
    func takesTheOthersSharesOutOfAPartlySplitMovement() {
        let dinner = dinner
        let debts = DebtLinks([owed(dinner, "300"), owed(dinner, "200", person: "Luis")])
        #expect(dinner.spendingAmount(debts: debts) == 400)
        #expect(dinner.isSplit(debts))
    }

    @Test
    func isZeroNeverBelowForAMovementOthersPaidForEntirely() {
        let dinner = dinner
        #expect(dinner.spendingAmount(debts: DebtLinks([owed(dinner, "450"), owed(dinner, "450")])) == 0)
        // A share larger than the movement (edited down since) still leaves zero.
        #expect(dinner.spendingAmount(debts: DebtLinks([owed(dinner, "1000")])) == 0)
    }

    @Test
    func countsASettledShareTooItWasNeverThePersonsSpending() {
        let dinner = dinner
        let settled = owed(dinner, "300", repayments: [DebtRepayment(amount: 300, date: dinner.date)], settledAt: dinner.date)
        #expect(dinner.spendingAmount(debts: DebtLinks([settled])) == 600)
    }

    @Test
    func ignoresDebtsThatArentTheyOweMeOrThatNameAnotherMovement() {
        let dinner = dinner
        let other = Fixtures.transaction(amount: "50", currency: "NIO", rate: .single("NIO"))
        #expect(dinner.spendingAmount(debts: DebtLinks([owed(dinner, "300", direction: .iOwe), owed(other, "10")])) == 900)
        #expect(!dinner.isSplit(DebtLinks([owed(other, "10")])))
        #expect(!dinner.isSplit(.empty))
    }

    @Test
    func onlyAnExpenseHasShares() {
        let income = Fixtures.transaction(.income, amount: "900", currency: "NIO", category: "salary", rate: .single("NIO"))
        let debts = DebtLinks([owed(income, "300")])
        #expect(income.spendingAmount(debts: debts) == 900)
        #expect(!income.isSplit(debts))
    }

    @Test
    func convertsAShareInTheMovementsCurrencyAtItsOwnRateRealChargeIncluded() {
        // NIO 3662.43 at 36.6243 is USD 100; Ana owes NIO 1220.81, a third.
        let lunch = Fixtures.transaction(amount: "3662.43", currency: "NIO")
        let debts = DebtLinks([owed(lunch, "1220.81")])
        #expect(lunch.spendingAmount(in: "USD", debts: debts)?.rounded(scale: 2) == Fixtures.decimal("66.67"))
        #expect(lunch.spendingAmount(in: "NIO", debts: debts) == Fixtures.decimal("2441.62"))
        // The bank charged USD 102: she owes a third of what it really cost.
        let charged = Fixtures.transaction(amount: "3662.43", currency: "NIO", actualDebited: "102")
        let chargedDebts = DebtLinks([owed(charged, "1220.81")])
        #expect(charged.spendingAmount(debts: chargedDebts).rounded(scale: 2) == 68)
    }

    @Test
    func convertsAShareInTheMovementsOtherCurrencyWithTheStoredRate() {
        let lunch = Fixtures.transaction(amount: "100")
        let share = owed(lunch, "1831.215", currency: "NIO")
        #expect(share.share(of: lunch, in: "USD") == 50)
        #expect(lunch.spendingAmount(debts: DebtLinks([share])) == 50)
    }

    @Test
    func ignoresAShareTheStoredRateCantConvertAndLeavesAnUnconvertibleMovementOut() {
        let lunch = Fixtures.transaction(amount: "100")
        let euros = owed(lunch, "20", currency: "EUR")
        #expect(euros.share(of: lunch, in: "USD") == nil)
        #expect(lunch.spendingAmount(debts: DebtLinks([euros])) == 100)
        // After the main currency became EUR, the movement itself can't reach it.
        #expect(lunch.spendingAmount(in: "EUR", debts: DebtLinks([owed(lunch, "30")])) == nil)
    }

    // MARK: Spending views

    /// Groceries 100, a dinner of 90 split with Ana (30, repaid and deposited) and Luis (30), and
    /// 40 that Eva owes in full; salary 1000 and Ana's deposit of 30.
    struct Ledger {
        let groceries: Transaction
        let shared: Transaction
        let salary: Transaction
        let deposit: Transaction
        let movements: [Transaction]
        let debts: [PersonalDebt]
    }

    static func ledger(account: UUID = UUID()) -> Ledger {
        let groceries = Fixtures.transaction(amount: "100", account: account, category: "groceries", date: Fixtures.date(2026, 10, 3))
        let shared = Fixtures.transaction(amount: "90", account: account, category: "restaurants", date: Fixtures.date(2026, 10, 5))
        let paidByOthers = Fixtures.transaction(amount: "40", account: account, category: "leisure", date: Fixtures.date(2026, 10, 6))
        let salary = Fixtures.transaction(
            .income, amount: "1000", account: account, category: "salary", date: Fixtures.date(2026, 10, 1),
        )
        let deposit = Fixtures.transaction(.income, amount: "30", account: account, category: "refunds", date: Fixtures.date(2026, 10, 7))
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
        return Ledger(
            groceries: groceries, shared: shared, salary: salary, deposit: deposit,
            movements: [groceries, shared, paidByOthers, salary, deposit], debts: [ana, luis, eva],
        )
    }

    @Test
    func theMonthlySummaryCountsThePersonsPartAndLeavesRepaymentDepositsOutOfIncome() {
        let ledger = Self.ledger()
        let summary = MonthlySummary(
            month: october, transactions: ledger.movements, currency: "USD", calendar: Fixtures.calendar, debts: DebtLinks(ledger.debts),
        )
        #expect(summary.expense == 130)
        #expect(summary.income == 1000)
        #expect(summary.categories.map(\.categoryID) == ["groceries", "restaurants"])
        #expect(summary.categories.map(\.amount) == [100, 30])
        #expect(summary.incomeCategories.map(\.categoryID) == ["salary"])
        #expect(summary.excluded.isEmpty)
        // Without debts, as before.
        let gross = MonthlySummary(month: october, transactions: ledger.movements, currency: "USD", calendar: Fixtures.calendar)
        #expect(gross.expense == 230)
        #expect(gross.income == 1030)
    }

    @Test
    func tellsADepositFromIncome() {
        let ledger = Self.ledger()
        let links = DebtLinks(ledger.debts)
        #expect(ledger.deposit.isReimbursement(links))
        #expect(!ledger.salary.isReimbursement(links))
        #expect(links.shares[ledger.shared.id]?.count == 2)
    }

    @Test
    func monthlyTotalsAndAveragesReadTheSameWay() {
        let ledger = Self.ledger()
        let links = DebtLinks(ledger.debts)
        func total(_ kind: TransactionKind) -> Decimal? {
            SpendingHistory.monthlyTotals(
                of: kind, endingAt: october, count: 1, transactions: ledger.movements, currency: "USD", calendar: Fixtures.calendar,
                debts: links,
            ).first?.total
        }
        #expect(total(.expense) == 130)
        #expect(total(.income) == 1000)
        let average = SpendingHistory.averageMonthlyTotal(
            of: .expense, transactions: ledger.movements, currency: "USD", calendar: Fixtures.calendar, debts: links,
        )
        #expect(average == 130)
    }

    @Test
    func anUnconvertibleMovementIsStillLeftOutAndReportedSplitOrNot() {
        let ledger = Self.ledger()
        let euros = Fixtures.transaction(amount: "50", currency: "EUR", date: Fixtures.date(2026, 10, 8), rate: .single("EUR"))
        let summary = MonthlySummary(
            month: october, transactions: ledger.movements + [euros], currency: "USD", calendar: Fixtures.calendar,
            debts: DebtLinks(ledger.debts + [owed(euros, "10")]),
        )
        #expect(summary.expense == 130)
        #expect(summary.excluded == [UnconvertedMovements(currency: "EUR", count: 1)])
    }

    @Test
    func budgetsCompareThePersonsPart() throws {
        let ledger = Self.ledger()
        let categories = TransactionCategory.defaults.map { category in
            category.id == "restaurants"
                ? TransactionCategory(id: category.id, name: category.name, kind: category.kind, monthlyBudget: Money(50, "USD"))
                : category
        }
        let summary = MonthlySummary(
            month: october, transactions: ledger.movements, currency: "USD", calendar: Fixtures.calendar, debts: DebtLinks(ledger.debts),
        )
        let status = try #require(CategoryBudgetStatus.statuses(of: summary, categories: categories).first)
        #expect(status.categoryID == "restaurants")
        #expect(status.spent.amount == 30)
        #expect(status.level == .onTrack)
    }

    @Test
    func theForecastsUsualSpendingAveragesThePersonsPart() throws {
        let ledger = Self.ledger()
        let november = try #require(YearMonth(year: 2026, month: 11))
        let links = DebtLinks(ledger.debts)
        let calendar = Fixtures.calendar
        let movements = ledger.movements
        #expect(BalanceForecast.averageUsualSpending(movements, before: november, currency: "USD", calendar: calendar, debts: links) == 130)
        #expect(BalanceForecast.averageUsualSpending(movements, before: november, currency: "USD", calendar: calendar) == 230)
    }

    @Test
    func balancesStillMoveByTheWholeMovementAndTheDeposit() {
        let account = Account(
            name: "Bank", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: Fixtures.date(2026, 9, 1),
        )
        let ledger = Self.ledger(account: account.id)
        let balance = Balances.balance(of: account, transactions: ledger.movements, calendar: Fixtures.calendar)
        // 1000 + 30 − 100 − 90 − 40.
        #expect(balance.first?.amount == Fixtures.decimal("800"))
    }

    // MARK: Repayments

    @Test
    func removingTheRepaymentThatSettledADebtReopensIt() throws {
        let dinner = dinner
        let debt = owed(dinner, "300")
        let repaid = try debt.repaying(300, on: dinner.date, transactionID: UUID())
        #expect(repaid.isSettled)
        let repayment = try #require(repaid.repayments.first)
        let (open, removed) = try repaid.removingRepayment(id: repayment.id)
        #expect(open.repayments.isEmpty)
        #expect(!open.isSettled)
        #expect(removed.transactionID == repayment.transactionID)
        #expect(throws: DomainError.notFound(repayment.id)) { try open.removingRepayment(id: repayment.id) }
    }

    @Test
    func keepsADebtSettledByHandSettledWhenARepaymentIsRemoved() throws {
        let dinner = dinner
        let repaid = try owed(dinner, "300").repaying(40, on: dinner.date)
        let byHand = repaid.settled(at: Fixtures.date(2026, 10, 30))
        let repayment = try #require(byHand.repayments.first)
        #expect(try byHand.removingRepayment(id: repayment.id).debt.settledAt == Fixtures.date(2026, 10, 30))
    }

    @Test
    func filesTheDepositUnderOtherIncomeOnceRefundsIsGoneAndNamesThePerson() {
        #expect(PersonalDebt.repaymentCategoryID(in: TransactionCategory.defaults) == "refunds")
        #expect(PersonalDebt.repaymentCategoryID(in: TransactionCategory.defaults.filter { $0.id != "refunds" }) == "other-income")
        let ana = PersonalDebt(person: "Ana", direction: .theyOweMe, amount: Money(1, "USD"), date: .now)
        #expect(ana.repaymentDescription == "Ana")
        let dinner = PersonalDebt(person: "Ana", direction: .theyOweMe, amount: Money(1, "USD"), date: .now, note: " Cena ")
        #expect(dinner.repaymentDescription == "Ana · Cena")
    }
}
