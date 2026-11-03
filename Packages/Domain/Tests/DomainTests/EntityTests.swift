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

    @Test(arguments: ["123", "12345", "12a4", "١٢٣٤"])
    func cardRejectsInvalidLastFour(value: String) {
        #expect(throws: DomainError.invalidLastFour(value)) {
            try Card(accountID: UUID(), kind: .debit, lastFour: value)
        }
    }
}
