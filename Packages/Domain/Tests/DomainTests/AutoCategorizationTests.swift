import Foundation
import Testing
@testable import Domain

/// Rules on every path (T26): a new movement without a category, or in "Other", takes the first
/// matching rule. The same cases run on the web (`tests/domain/categorization.test.ts`).
@Suite("Categorization rules on every path")
struct AutoCategorizationTests {
    private let uber = CategorizationRule(match: "uber", categoryID: "transport", kind: .expense, tags: ["trabajo"])
    private let anyTrip = CategorizationRule(match: "trip", categoryID: "travel", kind: .expense)
    private let calendar = Fixtures.calendar

    private func movement(_ description: String, category: String?, kind: TransactionKind = .expense) -> Transaction {
        Transaction(
            date: Fixtures.date(2026, 10, 5), description: description, kind: kind, categoryID: category,
            amount: 5, currency: "USD", accountID: UUID(), destinationAccountID: kind == .transfer ? UUID() : nil,
            exchangeRate: Fixtures.usdNio, tags: ["boda"],
        )
    }

    @Test
    func aMovementInOtherTakesTheRulesCategoryAndTags() {
        let categorized = CategorizationRules.autoCategorized(movement("Uber home", category: "other-expense"), rules: [uber])
        #expect(categorized.categoryID == "transport")
        #expect(categorized.tags == ["boda", "trabajo"])
        #expect(CategorizationRules.autoCategorized(movement("uber", category: nil), rules: [uber]).categoryID == "transport")
    }

    @Test
    func aChosenCategoryAndATransferStayAsTheyAre() {
        let chosen = movement("Uber eats", category: "restaurants")
        #expect(CategorizationRules.autoCategorized(chosen, rules: [uber]) == chosen)
        let transfer = movement("Uber", category: nil, kind: .transfer)
        #expect(CategorizationRules.autoCategorized(transfer, rules: [uber]) == transfer)
    }

    @Test
    func withTwoMatchingRulesTheFirstInOrderWins() {
        let other = movement("Uber trip", category: "other-expense")
        #expect(CategorizationRules.autoCategorized(other, rules: [anyTrip, uber]).categoryID == "travel")
        #expect(CategorizationRules.autoCategorized(other, rules: [uber, anyTrip]).categoryID == "transport")
    }

    @Test
    func aRuleWhoseCategoryIsGoneIsLeftOut() {
        let gone = CategorizationRule(match: "uber", categoryID: "deleted", kind: .expense)
        let wrongKind = CategorizationRule(match: "uber", categoryID: "salary", kind: .expense)
        #expect(CategorizationRules.usable([gone, wrongKind, uber], categories: TransactionCategory.defaults) == [uber])
    }

    @Test
    func anOccurrenceInOtherTakesTheMatchingRuleAndOneInAChosenCategoryStays() {
        func recurring(_ name: String, category: String) -> RecurringRule {
            RecurringRule(
                name: name, kind: .expense, categoryID: category, amount: 15, currency: "USD", accountID: UUID(),
                frequency: .monthly, startDate: Fixtures.date(2026, 11, 1, hour: 9),
            )
        }
        let netflix = CategorizationRule(match: "netflix", categoryID: "subscriptions", kind: .expense, tags: ["tv"])
        let result = RecurringSchedule.materialize(
            [recurring("Netflix", category: "other-expense"), recurring("Netflix and pizza", category: "groceries")],
            transactions: [],
            today: Fixtures.date(2026, 11, 6),
            exchangeRate: Fixtures.usdNio,
            calendar: calendar,
            categorizationRules: [netflix],
        )
        // Materialize walks rules by id, random here, so read the result by name.
        let byName = result.transactions.sorted { $0.description < $1.description }
        #expect(byName.map(\.categoryID) == ["subscriptions", "groceries"])
        #expect(byName.map(\.tags) == [["tv"], []])
    }
}
