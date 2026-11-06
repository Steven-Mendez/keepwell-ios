import Foundation
import Testing
@testable import Core

@Suite("App links")
struct AppLinkTests {
    @Test
    func newExpenseLinksCarryTheirCategory() {
        #expect(AppLink.newExpenseCategory(from: AppLink.newExpense(categoryID: "groceries")) == .some("groceries"))
        #expect(AppLink.newExpenseCategory(from: AppLink.newExpense()) == .some(nil))
    }

    @Test
    func otherLinksAreNotNewExpenses() throws {
        #expect(AppLink.newExpenseCategory(from: AppLink.home) == nil)
        let web = try #require(URL(string: "https://example.com/new-expense"))
        #expect(AppLink.newExpenseCategory(from: web) == nil)
    }

    @Test
    func aSnapshotSurvivesEncoding() throws {
        let snapshot = WidgetSnapshot(
            monthTitle: "October", spent: "$1.00", spentCaption: "spent", spentFraction: 0.5,
            netWorthTitle: "Net worth", netWorth: "$2.00", netWorthCaption: nil,
            balances: [.init(title: "Cash", value: "C$3")], shortcutsTitle: "Log quickly",
            shortcuts: [.init(categoryID: "groceries", title: "Groceries")], updatedAt: Date(timeIntervalSince1970: 0),
        )
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }
}
