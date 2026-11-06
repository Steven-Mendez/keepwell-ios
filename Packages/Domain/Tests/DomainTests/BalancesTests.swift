import Foundation
import Testing
@testable import Domain

@Suite("Account balances (rules 1, 3, 4, 5)")
struct BalancesTests {
    private let opening = Fixtures.date(2026, 9, 1)

    private func deposit(_ amount: String, _ currency: String = "USD") -> Account {
        Account(name: "Savings", kind: .deposit, openingBalances: [Money(Fixtures.decimal(amount), currency)], openingDate: opening)
    }

    private func balance(_ account: Account, _ transactions: [Transaction]) -> [Money] {
        Balances.balance(of: account, transactions: transactions, calendar: Fixtures.calendar)
    }

    @Test
    func expensesSubtractAndIncomeAdds() {
        let account = deposit("100")
        let result = balance(account, [
            Fixtures.transaction(.expense, amount: "30", account: account.id),
            Fixtures.transaction(.income, amount: "12.5", account: account.id),
        ])
        #expect(result == [Money(Fixtures.decimal("82.5"), "USD")])
    }

    @Test
    func plannedMovementsDoNotCount() {
        let account = deposit("100")
        let result = balance(account, [
            Fixtures.transaction(.expense, amount: "3500", currency: "NIO", account: account.id, status: .planned),
        ])
        #expect(result == [Money(100, "USD")])
    }

    @Test
    func confirmingAPlannedMovementMakesItCount() {
        let account = deposit("100")
        let planned = Fixtures.transaction(.expense, amount: "40", account: account.id, status: .planned)
        #expect(balance(account, [planned.confirmed()]) == [Money(60, "USD")])
    }

    @Test
    func movementsBeforeOpeningDateAreAlreadyInTheOpeningBalance() {
        let account = deposit("100")
        let old = Fixtures.transaction(.expense, amount: "40", account: account.id, date: Fixtures.date(2026, 8, 31))
        #expect(balance(account, [old]) == [Money(100, "USD")])
    }

    @Test
    func otherAccountsMovementsAreIgnored() {
        let account = deposit("100")
        #expect(balance(account, [Fixtures.transaction(.expense, amount: "40")]) == [Money(100, "USD")])
    }

    @Test
    func secondCurrencyPurchaseOnPrincipalAccountUsesRealDebit() {
        let account = deposit("100")
        let dinner = Fixtures.transaction(.expense, amount: "879", currency: "NIO", account: account.id, actualDebited: "24.28")
        #expect(balance(account, [dinner]) == [Money(Fixtures.decimal("75.72"), "USD")])
    }

    @Test
    func atmWithdrawalMovesSecondCurrencyIntoCashAndRealDebitOutOfBank() {
        let bank = deposit("100")
        let cash = deposit("0", "NIO")
        let withdrawal = Fixtures.transaction(
            .transfer, amount: "1200", currency: "NIO", account: bank.id, destination: cash.id, actualDebited: "33.15",
        )
        #expect(balance(bank, [withdrawal]) == [Money(Fixtures.decimal("66.85"), "USD")])
        #expect(balance(cash, [withdrawal]) == [Money(1200, "NIO")])
    }

    @Test
    func transfersAreNeitherExpenseNorIncomeButMoveMoney() {
        let from = deposit("500")
        let to = deposit("0")
        let move = Fixtures.transaction(.transfer, amount: "200", account: from.id, destination: to.id)
        #expect(balance(from, [move]) == [Money(300, "USD")])
        #expect(balance(to, [move]) == [Money(200, "USD")])
    }

    @Test
    func dualCreditCardBooksEachPurchaseInItsCurrency() {
        let card = Account(
            name: "Mastercard",
            kind: .credit,
            openingBalances: [Money(0, "USD"), Money(0, "NIO")],
            openingDate: opening,
        )
        let result = balance(card, [
            Fixtures.transaction(.expense, amount: "6.49", currency: "USD", account: card.id),
            Fixtures.transaction(.expense, amount: "190", currency: "NIO", account: card.id),
            Fixtures.transaction(.expense, amount: "10.30", currency: "USD", account: card.id),
            Fixtures.transaction(.expense, amount: "7.02", currency: "NIO", account: card.id),
        ])
        #expect(result == [Money(Fixtures.decimal("-16.79"), "USD"), Money(Fixtures.decimal("-197.02"), "NIO")])
    }

    @Test
    func payingTheSecondCurrencyDebtFromAPrincipalAccount() {
        let bank = deposit("100")
        let card = Account(
            name: "Mastercard",
            kind: .credit,
            openingBalances: [Money(0, "USD"), Money(-500, "NIO")],
            openingDate: opening,
        )
        let payment = Fixtures.transaction(
            .transfer, amount: "500", currency: "NIO", account: bank.id, destination: card.id, actualDebited: "13.70",
        )
        #expect(balance(card, [payment]) == [Money(0, "USD"), Money(0, "NIO")])
        #expect(balance(bank, [payment]) == [Money(Fixtures.decimal("86.30"), "USD")])
    }

    @Test
    func singleCurrencyCreditCardConvertsEverythingToItsCurrency() {
        let card = Account(name: "Visa", kind: .credit, openingBalances: [Money(-941.3, "NIO")], openingDate: opening)
        let purchase = Fixtures.transaction(.expense, amount: "10", currency: "USD", account: card.id)
        let result = balance(card, [purchase])
        #expect(result[0].amount.rounded(scale: 2) == Fixtures.decimal("-1307.54"))
    }
}
