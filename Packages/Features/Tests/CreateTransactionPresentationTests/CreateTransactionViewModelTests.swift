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
    func methodGroupsPutRecentAccountsFirst() async {
        let viewModel = await CreateTransactionFactory.loaded()
        viewModel.selectCategory("restaurants")
        #expect(viewModel.methodGroups.dropFirst(2).map(\.title) == ["Cash", "Credit cards"])
        #expect(viewModel.methodGroups.flatMap(\.rows).contains { $0.source == .card(SampleData.IDs.mastercardHolder) })
    }

    @Test
    func aBankAccountOffersOnlyItsCard() async {
        for kind in [MovementType.expense, .income] {
            let viewModel = await CreateTransactionFactory.loaded(kind)
            let sources = viewModel.methodGroups.flatMap(\.rows).map(\.source)
            #expect(sources.contains(.card(SampleData.IDs.savingsDebit)))
            #expect(!sources.contains(.card(SampleData.IDs.savingsTransfer)))
        }
    }

    @Test
    func aMovementLastPaidByTransferPreselectsTheAccountsCard() async throws {
        let viewModel = await CreateTransactionFactory.loaded()
        let context = try #require(viewModel.context)
        #expect(viewModel.pickerSource(for: .card(SampleData.IDs.savingsTransfer), in: context) == .card(SampleData.IDs.savingsDebit))
        #expect(viewModel.pickerSource(for: .card(SampleData.IDs.savingsDebit), in: context) == .card(SampleData.IDs.savingsDebit))
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

@Suite("Create transaction rules and tags")
@MainActor
struct CreateTransactionRulesTests {
    private func make(rules: [CategorizationRule]) async -> CreateTransactionViewModel {
        let sample = SampleData.standard
        let store = InMemoryStore(
            accounts: sample.accounts, cards: sample.cards, transactions: sample.transactions, settings: sample.settings,
        )
        for rule in rules {
            await store.save(rule)
        }
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store,
        )
        let viewModel = CreateTransactionViewModel(
            getContext: context,
            save: DefaultSaveTransactionUseCase(context: context, transactions: store),
        )
        await viewModel.load()
        viewModel.press(.digit(5))
        viewModel.continueFromAmount()
        return viewModel
    }

    private let uber = CategorizationRule(match: "uber", categoryID: "transport", kind: .expense, tags: ["trabajo"])

    @Test
    func aRuleChoosesTheCategoryWhenThePersonPickedOther() async {
        let viewModel = await make(rules: [uber])
        viewModel.selectCategory(TransactionCategory.otherExpenseID)
        viewModel.description = "UBER *TRIP"
        #expect(viewModel.categoryID == "transport")
        #expect(viewModel.tags == ["trabajo"])
        #expect(viewModel.ruleHint == "Category from rule: uber")
        #expect(viewModel.draft.tags == ["trabajo"])
        // The text stops matching: the earlier category and the rule's tags go back.
        viewModel.description = "Bus"
        #expect(viewModel.categoryID == TransactionCategory.otherExpenseID)
        #expect(viewModel.tags.isEmpty)
        #expect(viewModel.ruleHint == nil)
    }

    @Test
    func aCategoryThePersonPickedStays() async {
        let viewModel = await make(rules: [uber])
        viewModel.selectCategory("restaurants")
        viewModel.note = "uber eats"
        #expect(viewModel.categoryID == "restaurants")
        #expect(viewModel.ruleHint == nil)
    }

    @Test
    func aWidgetPresetCanStillBeReplacedByARule() async {
        let viewModel = await make(rules: [uber])
        viewModel.selectCategory("groceries", byPerson: false)
        viewModel.description = "Uber"
        #expect(viewModel.categoryID == "transport")
        // Picking one by hand takes over.
        viewModel.selectCategory("health")
        viewModel.description = "Uber again"
        #expect(viewModel.categoryID == "health")
        #expect(viewModel.ruleHint == nil)
    }
}
