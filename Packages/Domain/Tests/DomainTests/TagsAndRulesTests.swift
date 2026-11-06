import Foundation
import Testing
@testable import Domain

/// The same cases run on the web (`tests/domain/categorization.test.ts`), so both apps store the
/// same tag for the same text and pick the same rule.
@Suite("Tags and categorization rules")
struct TagsAndRulesTests {
    @Test(arguments: [
        ("#Viaje México", "viaje-méxico"),
        ("  ##boda  ", "boda"),
        ("Fin de  semana\tlargo", "fin-de-semana-largo"),
        ("ÑANDÚ", "ñandú"),
        ("me\u{301}xico", "méxico"),
        ("# - boda - ", "boda"),
        (String(repeating: "a", count: 40), String(repeating: "a", count: 32)),
        (String(repeating: "a", count: 31) + " b", String(repeating: "a", count: 31)),
        ("café#2", "café#2"),
    ])
    func aTagIsNormalizedTheSameOnBothApps(raw: String, expected: String) {
        #expect(Tags.normalized(raw) == expected)
    }

    @Test(arguments: ["", "   ", "#", "## ", " - "])
    func blankTagsAreDropped(raw: String) {
        #expect(Tags.normalized(raw) == nil)
    }

    @Test
    func aListKeepsEachTagOnceInTheOrderFirstGiven() {
        #expect(Tags.normalized(["Boda", "#viaje", "#boda", " ", "VIAJE"]) == ["boda", "viaje"])
        #expect(Tags.merging(["boda"], with: ["viaje", "Boda"]) == ["boda", "viaje"])
    }

    @Test
    func aMovementStoresItsTagsNormalized() {
        let movement = Fixtures.transaction(amount: "5").with(categoryID: "transport", tags: ["#Boda", "boda", "Viaje México"])
        #expect(movement.tags == ["boda", "viaje-méxico"])
    }

    @Test
    func suggestionsPutTheMostUsedFirstAndLeaveOutTheChosenOnes() {
        let base = Fixtures.transaction(amount: "5")
        let movements = [
            base.with(categoryID: nil, tags: ["viaje", "boda"]),
            base.with(categoryID: nil, tags: ["boda"]),
            base.with(categoryID: nil, tags: ["boda", "casa"]),
            base.with(categoryID: nil, tags: ["casa"]),
        ]
        let usage = Tags.usage(in: movements)
        #expect(usage == ["boda", "casa", "viaje"])
        #expect(Tags.suggestions(from: usage, typing: "", excluding: ["casa"]) == ["boda", "viaje"])
        #expect(Tags.suggestions(from: usage, typing: "#A", excluding: []) == ["boda", "casa", "viaje"])
        #expect(Tags.suggestions(from: usage, typing: "vi", excluding: []) == ["viaje"])
    }

    @Test(arguments: [
        ("#boda", "boda"),
        ("  # Viaje México ", "viaje-méxico"),
    ])
    func aHashSearchAsksForThatTag(query: String, expected: String) {
        #expect(Tags.searched(in: query) == expected)
    }

    @Test(arguments: ["boda", "", "#", "café #boda"])
    func otherSearchesAskForNoTag(query: String) {
        #expect(Tags.searched(in: query) == nil)
    }

    // MARK: - Rules

    private let uber = CategorizationRule(match: "uber", categoryID: "transport", kind: .expense, tags: ["#Trabajo"])
    private let cafe = CategorizationRule(match: "Cafe", categoryID: "restaurants", kind: .expense)
    private let anyTrip = CategorizationRule(match: "trip", categoryID: "travel", kind: .expense)
    private let payroll = CategorizationRule(match: "payroll", categoryID: "salary", kind: .income)

    @Test
    func aRuleMatchesWithoutCaseOrAccentsInTheDescriptionOrNote() {
        #expect(uber.matches(kind: .expense, description: "UBER *TRIP 1234", note: nil))
        #expect(cafe.matches(kind: .expense, description: "Café París", note: nil))
        #expect(cafe.matches(kind: .expense, description: "Breakfast", note: "at the café"))
        #expect(!cafe.matches(kind: .income, description: "Café París", note: nil))
        #expect(!CategorizationRule(match: "  ", categoryID: "transport", kind: .expense).matches(
            kind: .expense,
            description: "x",
            note: nil,
        ))
        #expect(uber.tags == ["trabajo"])
    }

    @Test
    func theFirstRuleInOrderWins() {
        let rules = [anyTrip, uber, payroll]
        #expect(CategorizationRules.firstMatch(in: rules, kind: .expense, description: "Uber trip", note: nil) == anyTrip)
        #expect(CategorizationRules.firstMatch(in: [uber, anyTrip], kind: .expense, description: "Uber trip", note: nil) == uber)
        #expect(CategorizationRules.firstMatch(in: rules, kind: .income, description: "ACME PAYROLL", note: nil) == payroll)
        #expect(CategorizationRules.firstMatch(in: rules, kind: .expense, description: "Groceries", note: nil) == nil)
    }

    @Test
    func validatingTrimsTheTextAndChecksTheCategoryAndKind() throws {
        let categories = TransactionCategory.defaults
        let saved = try CategorizationRule(match: "  Uber  ", categoryID: "transport", kind: .expense).validated(categories: categories)
        #expect(saved.match == "Uber")
        #expect(throws: DomainError.missingName) {
            try CategorizationRule(match: " ", categoryID: "transport", kind: .expense).validated(categories: categories)
        }
        #expect(throws: DomainError.categoryKindMismatch(expected: .income, actual: .expense)) {
            try CategorizationRule(match: "x", categoryID: "transport", kind: .income).validated(categories: categories)
        }
        #expect(throws: DomainError.unsupportedTransactionKind(.transfer)) {
            try CategorizationRule(match: "x", categoryID: "transport", kind: .transfer).validated(categories: categories)
        }
        let long = try CategorizationRule(match: String(repeating: "x", count: 80), categoryID: "transport", kind: .expense)
            .validated(categories: categories)
        #expect(long.match.count == CategorizationRule.maxMatchLength)
    }

    @Test
    func applyingToPastChangesOnlyUncategorizedMatchingMovementsOfItsKind() {
        func movement(_ description: String, category: String?, kind: TransactionKind = .expense) -> Transaction {
            Transaction(
                date: Fixtures.date(2026, 10, 5), description: description, kind: kind, categoryID: category,
                amount: 5, currency: "USD", accountID: UUID(), exchangeRate: Fixtures.usdNio, tags: ["boda"],
            )
        }
        let other = movement("Uber home", category: "other-expense")
        let none = movement("uber", category: nil)
        let categorized = movement("Uber eats", category: "restaurants")
        let unrelated = movement("Bus", category: "other-expense")
        let income = movement("Uber refund", category: "other-income", kind: .income)
        let matches = CategorizationRules.pastMatches(of: uber, in: [other, none, categorized, unrelated, income])
        #expect(matches.map(\.id) == [other.id, none.id])
        let applied = CategorizationRules.applying(uber, to: other)
        #expect(applied.categoryID == "transport")
        #expect(applied.tags == ["boda", "trabajo"])
        #expect(applied.id == other.id && applied.amount == other.amount)
    }

    @Test
    func aRecurringRuleHandsItsTagsToTheMovementsItRecords() {
        let rule = RecurringRule(
            name: "Gym", kind: .expense, categoryID: "health", amount: 30, currency: "USD", accountID: UUID(),
            frequency: .monthly, startDate: Fixtures.date(2026, 1, 1), tags: ["#Salud"],
        )
        #expect(rule.with(nextDate: Fixtures.date(2026, 2, 1)).tags == ["salud"])
        let movement = RecurringSchedule.movement(from: rule, on: Fixtures.date(2026, 1, 1), exchangeRate: Fixtures.usdNio)
        #expect(movement.tags == ["salud"])
    }
}
