import Foundation
import Testing
@testable import Domain

@Suite("Entities")
struct EntityTests {
    @Test
    func defaultCategoriesMatchHandoff() {
        #expect(TransactionCategory.defaultExpense.count == 22)
        #expect(TransactionCategory.defaultIncome.count == 9)
        #expect(TransactionCategory.defaultExpense.allSatisfy { $0.kind == .expense })
        #expect(TransactionCategory.defaultIncome.allSatisfy { $0.kind == .income })
        #expect(Set(TransactionCategory.defaults.map(\.id)).count == TransactionCategory.defaults.count)
    }

    @Test(arguments: [0, 32, -1])
    func creditTermsRejectInvalidDays(day: Int) {
        #expect(throws: DomainError.invalidDayOfMonth(day)) { try CreditTerms(debtMode: .dual, cutoffDay: day) }
        #expect(throws: DomainError.invalidDayOfMonth(day)) { try CreditTerms(debtMode: .dual, dueDay: day) }
    }

    @Test
    func creditTermsAcceptDayRange() throws {
        let terms = try CreditTerms(debtMode: .dual, cutoffDay: 31, dueDay: 1)
        #expect(terms.cutoffDay == 31)
    }

    @Test
    func dualCreditAccountHoldsTwoCurrencies() {
        let account = Account(
            name: "Mastercard",
            kind: .credit,
            openingBalances: [Money(0, "USD"), Money(0, "NIO")],
            openingDate: .now,
        )
        #expect(account.currencies == ["USD", "NIO"])
    }

    /// Ties go to the even neighbor, so rounding many converted amounts doesn't drift upward.
    @Test(arguments: [("0.125", 2, "0.12"), ("0.135", 2, "0.14"), ("-0.125", 2, "-0.12"), ("2.5", 0, "2")])
    func roundingDefaultsToBankers(value: String, scale: Int, expected: String) {
        #expect(Fixtures.decimal(value).rounded(scale: scale) == Fixtures.decimal(expected))
    }

    @Test
    func roundingHalfUpIsStillAvailable() {
        #expect(Fixtures.decimal("0.125").rounded(scale: 2, mode: .plain) == Fixtures.decimal("0.13"))
    }

    @Test(arguments: [("0", nil), ("-50", nil), ("10", "0"), ("10", "-1")] as [(String, String?)])
    func transactionAmountsMustBePositive(amount: String, debited: String?) {
        #expect(throws: DomainError.invalidAmount) {
            try Transaction.checkAmounts(Fixtures.decimal(amount), actualDebitedPrincipal: debited.map(Fixtures.decimal))
        }
    }

    @Test
    func positiveTransactionAmountsPass() throws {
        try Transaction.checkAmounts(Fixtures.decimal("0.01"))
        try Transaction.checkAmounts(Fixtures.decimal("879"), actualDebitedPrincipal: Fixtures.decimal("24.28"))
    }

    @Test(arguments: ["123", "12345", "12a4", "١٢٣٤"])
    func cardRejectsInvalidLastFour(value: String) {
        #expect(throws: DomainError.invalidLastFour(value)) {
            try Card(accountID: UUID(), kind: .debit, lastFour: value)
        }
    }
}
