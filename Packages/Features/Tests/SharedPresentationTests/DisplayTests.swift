import Core
import Domain
import Foundation
import Testing
@testable import SharedPresentation

@Suite("Display mappings")
struct DisplayTests {
    @Test
    func cardNamesAndWordmarks() throws {
        let account = Account(name: "Savings", bank: "Bank One", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .now)
        let debit = try Card(accountID: account.id, kind: .debit, network: .visa, lastFour: "1234", color: .coral)
        let transfer = try Card(accountID: account.id, kind: .transfer)
        #expect(CardDisplay.name(of: account) == "Bank One Savings")
        #expect(CardDisplay.methodTitle(debit, account: account) == "Debit •••• 1234")
        #expect(CardDisplay.methodTitle(transfer, account: account) == "Bank One · Bank transfer")
        #expect(CardDisplay.shortName(of: debit) == "Visa ··1234")
        #expect(CardDisplay.wordmark(for: .mastercard) == "mastercard")
        #expect(CardDisplay.palette(for: .lima) == .lima)
        #expect(CardDisplay.cardColor(for: .oro) == .oro)
    }

    @Test
    func creditCardsReadAsTheirNumberNotTheirRole() throws {
        let account = Account(name: "Visa", bank: "Bank One", kind: .credit, openingBalances: [Money(0, "USD")], openingDate: .now)
        let holder = try Card(accountID: account.id, kind: .creditHolder, network: .visa, lastFour: "3141")
        let unnamedBank = Account(name: " ", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .now)
        let transfer = try Card(accountID: unnamedBank.id, kind: .transfer)
        #expect(CardDisplay.methodTitle(holder, account: account) == "Visa •••• 3141")
        #expect(CardDisplay.methodTitle(transfer, account: unnamedBank) == "Bank transfer")
    }

    @Test
    func joinedBalancesLikeTheCards() {
        let formatter = CurrencyFormatter()
        let text = formatter.joined([Money(Decimal(string: "-197.02") ?? 0, "NIO"), Money(Decimal(string: "-16.79") ?? 0, "USD")])
        #expect(text == "−C$197.02 · −$16.79")
    }

    @Test
    func defaultCategoriesTranslateByIDAndCustomOnesKeepTheirName() {
        let groceries = TransactionCategory(id: "groceries", name: "Groceries", kind: .expense)
        let renamed = TransactionCategory(id: "groceries", name: "Market", kind: .expense)
        let custom = TransactionCategory(id: "pets", name: "Pets", kind: .expense)
        #expect(CategoryDisplay.name(of: groceries) == "Groceries")
        #expect(CategoryDisplay.name(of: renamed) == "Market")
        #expect(CategoryDisplay.name(of: custom) == "Pets")
    }
}
