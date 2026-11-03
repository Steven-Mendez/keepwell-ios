import Foundation
import Testing
@testable import Domain

@Suite("Entities")
struct EntityTests {
    @Test
    func defaultCategoriesMatchHandoff() {
        #expect(TransactionCategory.defaultExpense.count == 16)
        #expect(TransactionCategory.defaultIncome.count == 5)
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

    @Test
    func additionalControlsOnlyStickToAdditionalCards() throws {
        let controls = AdditionalCardControls(holderName: "Familiar")
        let holder = try Card(accountID: UUID(), kind: .creditHolder, lastFour: "1234", additional: controls)
        let additional = try Card(accountID: UUID(), kind: .creditAdditional, lastFour: "5678", additional: controls)
        #expect(holder.additional == nil)
        #expect(additional.additional == controls)
    }

    @Test
    func additionalCardAllowsOnlyItsCategoriesAndNothingWhenFrozen() {
        let open = AdditionalCardControls(holderName: "A")
        let limited = AdditionalCardControls(holderName: "B", allowedCategoryIDs: ["groceries", "health"])
        let frozen = AdditionalCardControls(holderName: "C", isFrozen: true)
        #expect(open.allows(categoryID: "travel"))
        #expect(limited.allows(categoryID: "groceries"))
        #expect(!limited.allows(categoryID: "travel"))
        #expect(!frozen.allows(categoryID: "groceries"))
    }
}
