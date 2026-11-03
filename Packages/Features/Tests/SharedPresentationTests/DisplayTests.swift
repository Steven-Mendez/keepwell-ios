import Core
import DesignSystem
import Domain
import Foundation
import Testing
import UIKit
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
        // A bank account's card saved without digits still reads as a card.
        #expect(try CardDisplay.methodTitle(Card.debit(for: account.id), account: account) == "Debit card")
        #expect(CardDisplay.networkMark(for: .mastercard) == .mastercard)
        #expect(CardDisplay.networkMark(for: .other) == nil)
        #expect(CardDisplay.numberGroups(for: .amex) == [4, 6, 5])
        #expect(CardDisplay.palette(for: .lima) == .lima)
        #expect(CardDisplay.cardColor(for: .oro) == .oro)
    }

    @Test
    func cardFacesPrintTheNumberAsTheNetworkGroupsIt() {
        #expect(KWCardArt.maskedNumber(lastFour: "6019") == "•••• •••• •••• 6019")
        #expect(KWCardArt.maskedNumber(lastFour: "6019", groups: CardDisplay.numberGroups(for: .amex)) == "•••• •••••• •6019")
        #expect(CardDisplay.kindLabel(.debit) == "Debit")
        #expect(CardDisplay.kindLabel(.creditAdditional) == "Credit")
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
        let renamed = TransactionCategory(id: "groceries", name: "Market", kind: .expense, isRenamed: true)
        let custom = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense)
        #expect(CategoryDisplay.name(of: groceries) == "Groceries")
        #expect(CategoryDisplay.name(of: renamed) == "Market")
        #expect(CategoryDisplay.name(of: custom) == "Boat")
    }

    @Test
    func everyDefaultHasItsOwnIconWithinItsKind() {
        for kind in [TransactionKind.expense, .income] {
            let symbols = TransactionCategory.defaults.filter { $0.kind == kind }.map(CategoryDisplay.symbol(for:))
            #expect(Set(symbols).count == symbols.count)
        }
        #expect(TransactionCategory.defaults.allSatisfy { CategoryDisplay.defaultSymbol(for: $0.id) != nil })
    }

    @Test
    func everyIconExistsInSFSymbols() {
        let symbols = Set(TransactionCategory.defaults.map(CategoryDisplay.symbol(for:)) + CategoryDisplay.symbolChoices)
        let missing = symbols.filter { UIImage(systemName: $0) == nil }
        #expect(missing.isEmpty)
        #expect(Set(CategoryDisplay.symbolChoices).count == CategoryDisplay.symbolChoices.count)
    }

    @Test
    func createdCategoriesUseTheirOwnIconAndColor() {
        let boat = TransactionCategory(id: "custom-boat", name: "Boat", kind: .expense, icon: "sailboat", color: "blue")
        #expect(CategoryDisplay.symbol(for: boat) == "sailboat")
        #expect(CategoryDisplay.symbol(for: nil) == CategoryDisplay.fallbackSymbol)
        #expect(CategoryDisplay.color(for: boat) == KWColor.categoryPalette(key: "blue"))
        #expect(CategoryDisplay.colorChoices.count == KWColor.categoryPalette.count)
    }
}
