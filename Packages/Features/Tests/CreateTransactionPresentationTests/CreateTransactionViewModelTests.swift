import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionPresentation

@MainActor
enum CreateTransactionFactory {
    nonisolated static let now = SampleData.defaultReferenceDate

    static func make(
        kind: TransactionKind = .expense,
        store: InMemoryStore = InMemoryStore(sample: .standard),
    ) -> CreateTransactionViewModel {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { now },
        )
        return CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(context: context, transactions: store),
            kind: kind,
            now: { now },
        )
    }

    static func loaded(kind: TransactionKind = .expense) async -> CreateTransactionViewModel {
        let viewModel = make(kind: kind)
        await viewModel.load()
        return viewModel
    }
}

@Suite("Create transaction view model")
@MainActor
struct CreateTransactionViewModelTests {
    private func type(_ viewModel: CreateTransactionViewModel, _ keys: String) {
        for character in keys {
            if character == "." {
                viewModel.press(.dot)
            } else if character == "<" {
                viewModel.press(.delete)
            } else if let digit = character.wholeNumberValue {
                viewModel.press(.digit(digit))
            }
        }
    }

    @Test
    func keypadFollowsTheDesignRules() async {
        let viewModel = await CreateTransactionFactory.loaded()
        type(viewModel, "0879")
        #expect(viewModel.amountText == "879")
        type(viewModel, "..5")
        #expect(viewModel.amountText == "879.5")
        type(viewModel, "55")
        #expect(viewModel.amountText == "879.55")
        type(viewModel, "<<<<<<<")
        #expect(viewModel.amountText == "0")
        type(viewModel, "1234567890")
        #expect(viewModel.amountText == "123456789")
    }

    @Test
    func amountDisplayAndConversionUseTheSecondCurrencyByDefault() async {
        let viewModel = await CreateTransactionFactory.loaded()
        type(viewModel, "879")
        #expect(viewModel.currency == "NIO")
        #expect(viewModel.amountDisplay == "−C$879")
        #expect(viewModel.conversionLine == "≈ $24.00 · 1 USD = 36.6243 NIO")
        viewModel.setKind(.income)
        #expect(viewModel.amountDisplay == "+C$879")
        viewModel.currency = "USD"
        #expect(viewModel.conversionLine == "≈ C$32,192.76 · 1 USD = 36.6243 NIO")
    }

    @Test
    func zeroAmountCannotContinue() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(!viewModel.canContinueFromAmount)
        viewModel.continueFromAmount()
        #expect(viewModel.path.isEmpty)
    }

    @Test
    func categoriesShowEightMostUsedThenAllOrSearch() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(viewModel.visibleCategories.count == 8)
        #expect(viewModel.hasMoreCategories)
        viewModel.showsAllCategories = true
        #expect(viewModel.visibleCategories.count == 16)
        viewModel.categoryQuery = "groc"
        #expect(viewModel.visibleCategories.map(\.id) == ["groceries"])
    }

    @Test
    func methodGroupsPutRecentAccountsFirstAndHideBlockedAdditionals() async {
        let viewModel = await CreateTransactionFactory.loaded()
        viewModel.selectCategory("restaurants")
        let sources = viewModel.methodGroups.flatMap(\.rows).map(\.source)
        #expect(!sources.contains(.card(SampleData.IDs.mastercardAdditional)))
        #expect(viewModel.methodGroups.last?.title == "Other")
        #expect(viewModel.methodGroups.count == 3)
        viewModel.path = [.category]
        viewModel.selectCategory("groceries")
        #expect(viewModel.methodGroups.flatMap(\.rows).contains { $0.source == .card(SampleData.IDs.mastercardAdditional) })
    }

    @Test
    func fullExpenseFlowSavesAndShowsTheResult() async throws {
        let viewModel = await CreateTransactionFactory.loaded()
        type(viewModel, "879")
        viewModel.continueFromAmount()
        viewModel.selectCategory("restaurants")
        viewModel.selectSource(.card(SampleData.IDs.savingsDebit))
        #expect(viewModel.path == [.category, .method, .review])
        #expect(viewModel.showsDebitedField)
        #expect(viewModel.reviewSubtitle == "Restaurants · Debit •••• 1234")
        #expect(viewModel.accountLabel(viewModel.sourceAccount) == "Bank One Savings (USD)")
        viewModel.debitedText = "24.28"
        viewModel.description = "Chicken"
        await viewModel.save()
        #expect(viewModel.path.last == .saved)
        let saved = try #require(viewModel.saved)
        #expect(saved.transaction.actualDebitedPrincipal == Decimal(string: "24.28"))
        #expect(saved.transaction.status == .confirmed)
    }

    @Test
    func plannedChangesTheCopy() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(viewModel.saveTitle == "Save expense")
        #expect(viewModel.plannedHint == "Already happened: counts in balances")
        viewModel.isPlanned = true
        #expect(viewModel.saveTitle == "Save as planned")
        #expect(viewModel.plannedHint == "Doesn't count until confirmed")
    }

    @Test
    func transferPicksADestinationThenExcludesItAsSource() async {
        let viewModel = await CreateTransactionFactory.loaded(kind: .transfer)
        type(viewModel, "500")
        viewModel.continueFromAmount()
        viewModel.selectDestination(SampleData.IDs.cash)
        #expect(!viewModel.methodGroups.flatMap(\.rows).contains { $0.source == .account(SampleData.IDs.cash) })
        viewModel.selectSource(.card(SampleData.IDs.savingsTransfer))
        await viewModel.save()
        #expect(viewModel.saved?.transaction.destinationAccountID == SampleData.IDs.cash)
    }

    @Test
    func startOverKeepsTypeAndClearsTheRest() async {
        let viewModel = await CreateTransactionFactory.loaded()
        type(viewModel, "12")
        viewModel.description = "x"
        await viewModel.startOver()
        #expect(viewModel.amountText == "0")
        #expect(viewModel.description.isEmpty)
        #expect(viewModel.path.isEmpty)
    }

    @Test
    func dayLabels() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(viewModel.dayLabel(CreateTransactionFactory.now).hasPrefix("Today, "))
    }
}
