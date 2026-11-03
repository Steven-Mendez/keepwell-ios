import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionPresentation

@MainActor
enum CreateTransactionFactory {
    nonisolated static let now = SampleData.defaultReferenceDate
    /// Fixed so the receipt's reference doesn't change between snapshot runs.
    nonisolated static let movementID = UUID(uuidString: "7E1A2B3C-0000-4000-8000-000000000001") ?? UUID()

    static func make(
        type: MovementType = .expense,
        store: InMemoryStore = InMemoryStore(sample: .standard),
        receiptSaver: (any ReceiptImageSaving)? = nil,
    ) -> CreateTransactionViewModel {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, now: { now },
        )
        return CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(context: context, transactions: store),
            saveCategory: DefaultSaveCategoryUseCase(categories: store),
            receiptSaver: receiptSaver,
            type: type,
            now: { now },
            makeID: { movementID },
        )
    }

    static func loaded(_ type: MovementType = .expense) async -> CreateTransactionViewModel {
        let viewModel = make(type: type)
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
        let income = await CreateTransactionFactory.loaded(.income)
        type(income, "879")
        #expect(income.amountDisplay == "+C$879")
        income.currency = "USD"
        #expect(income.conversionLine == "≈ C$32,192.76 · 1 USD = 36.6243 NIO")
    }

    @Test
    func zeroAmountCannotContinue() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(!viewModel.canContinueFromAmount)
        viewModel.continueFromAmount()
        #expect(viewModel.path.isEmpty)
    }

    @Test
    func categoriesShowTheMostUsedThenAllOrSearch() async {
        let viewModel = await CreateTransactionFactory.loaded()
        // Ten categories, then "See all" and "New category" fill four rows of three.
        #expect(viewModel.visibleCategories.count == 10)
        #expect(viewModel.hasMoreCategories)
        #expect(viewModel.canCreateCategory)
        viewModel.showsAllCategories = true
        #expect(viewModel.visibleCategories.count == TransactionCategory.defaultExpense.count)
        viewModel.categoryQuery = "groc"
        #expect(viewModel.visibleCategories.map(\.id) == ["groceries"])
    }

    @Test
    func aShortListShowsEverythingWithoutSeeAll() async {
        let viewModel = await CreateTransactionFactory.loaded(.income)
        #expect(!viewModel.hasMoreCategories)
        #expect(viewModel.visibleCategories.count == TransactionCategory.defaultIncome.count)
    }

    @Test
    func aNewCategoryStartsFromTheSearchAndIsChosenOnceCreated() async throws {
        let viewModel = await CreateTransactionFactory.loaded()
        type(viewModel, "12")
        viewModel.continueFromAmount()
        viewModel.categoryQuery = "Boat"
        #expect(viewModel.visibleCategories.isEmpty)
        viewModel.startNewCategory()
        let editor = try #require(viewModel.categoryEditor)
        #expect(editor.name == "Boat")
        #expect(editor.kind == .expense)
        let created = try #require(await editor.save())
        viewModel.categoryCreated(created)
        #expect(viewModel.categoryEditor == nil)
        #expect(viewModel.categoryQuery.isEmpty)
        #expect(viewModel.categoryID == created.id)
        #expect(viewModel.categories.contains(created))
        #expect(viewModel.path == [.category, .method])
    }

    @Test
    func transfersCantCreateCategories() async {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        #expect(!viewModel.canCreateCategory)
        viewModel.startNewCategory()
        #expect(viewModel.categoryEditor == nil)
    }

    @Test
    func methodGroupsPutRecentAccountsFirstAndHideBlockedAdditionals() async {
        let viewModel = await CreateTransactionFactory.loaded()
        viewModel.selectCategory("restaurants")
        let sources = viewModel.methodGroups.flatMap(\.rows).map(\.source)
        #expect(!sources.contains(.card(SampleData.IDs.mastercardAdditional)))
        #expect(viewModel.methodGroups.dropFirst(2).map(\.title) == ["Cash", "Credit cards"])
        viewModel.path = [.category]
        viewModel.selectCategory("groceries")
        #expect(viewModel.methodGroups.flatMap(\.rows).contains { $0.source == .card(SampleData.IDs.mastercardAdditional) })
    }

    @Test
    func theAccountsCardlessMethodSitsUnderItsCardWordedForAnExpense() async throws {
        let viewModel = await CreateTransactionFactory.loaded()
        viewModel.selectCategory("restaurants")
        let rows = viewModel.methodGroups.flatMap(\.rows)
        let transfer = try #require(rows.first { $0.source == .card(SampleData.IDs.savingsTransfer) })
        #expect(transfer.title == "Transfer or direct debit")
        #expect(transfer.thumbnail == .transfer)
        #expect(["Without the card, straight from the account", "Without the card, from Bank One Savings"]
            .contains(transfer.subtitle ?? ""))
        let savingsRows = rows.filter { [.card(SampleData.IDs.savingsDebit), .card(SampleData.IDs.savingsTransfer)].contains($0.source) }
        #expect(savingsRows.map(\.source) == [.card(SampleData.IDs.savingsDebit), .card(SampleData.IDs.savingsTransfer)])
        #expect(!rows.contains { ["Holder", "Transfer"].contains($0.title) || $0.subtitle == "Credit · holder" })
        viewModel.selectSource(.card(SampleData.IDs.savingsTransfer))
        #expect(viewModel.sourceTitle == "Bank One · Bank transfer")
    }

    @Test
    func incomeIntoTheAccountIsNotWordedAsACharge() async throws {
        let viewModel = await CreateTransactionFactory.loaded(.income)
        let rows = viewModel.methodGroups.flatMap(\.rows)
        let transfer = try #require(rows.first { $0.source == .card(SampleData.IDs.savingsTransfer) })
        #expect(transfer.title == "Transfer or deposit")
        #expect(["Straight into the account", "Straight into Bank One Savings"].contains(transfer.subtitle ?? ""))
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
