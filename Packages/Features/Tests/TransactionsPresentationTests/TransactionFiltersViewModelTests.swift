import Domain
import DomainSamples
import Foundation
import Testing
import TransactionsDomain
@testable import TransactionsPresentation

/// The amount and origin filters on the list: the active chips, their ✕, and opening the list from
/// a recurring rule.
@Suite("Transactions filters")
@MainActor
struct TransactionFiltersViewModelTests {
    private typealias IDs = SampleData.IDs

    /// The sample ledger plus one movement each from the streaming subscription and the rent.
    static func filteredStore() async -> InMemoryStore {
        let store = InMemoryStore(sample: .standard)
        let rate = (try? ExchangeRate(principal: "USD", second: "NIO", rate: Decimal(string: "36.6243") ?? 1)) ?? .single("USD")
        for (rule, name, amount, currency) in [
            (IDs.streamingRule, "Streaming", Decimal(string: "15.99") ?? 0, "USD"),
            (IDs.rentRule, "Rent", Decimal(18000), "NIO"),
        ] {
            await store.save(Transaction(
                date: SampleData.defaultReferenceDate, description: name, kind: .expense, categoryID: "subscriptions",
                amount: amount, currency: currency, accountID: IDs.savings, exchangeRate: rate, recurringID: rule,
            ))
        }
        return store
    }

    static func loaded() async -> TransactionsViewModel {
        let store = await filteredStore()
        let viewModel = TransactionsViewModel(
            getList: DefaultGetTransactionListUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store, recurringRules: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
            now: { SampleData.defaultReferenceDate },
        )
        await viewModel.load()
        return viewModel
    }

    private func rows(_ viewModel: TransactionsViewModel) -> [Transaction] {
        viewModel.sections.flatMap(\.transactions)
    }

    @Test
    func noFiltersMeansNoChipsAndTheWholeList() async {
        let viewModel = await Self.loaded()
        #expect(viewModel.activeFilters.isEmpty)
        #expect(rows(viewModel).count == viewModel.list?.transactions.count)
    }

    @Test
    func activeFiltersShowAsChipsAndNarrowTheList() async {
        let viewModel = await Self.loaded()
        viewModel.amount = AmountRange(min: 100)
        #expect(viewModel.activeFilters.map(\.title) == ["≥ $100"])
        #expect(rows(viewModel).allSatisfy { $0.amount(in: "USD").rounded(scale: 2, mode: .plain) >= 100 })
        viewModel.amount = AmountRange(max: Decimal(string: "500.5"))
        #expect(viewModel.activeFilters.map(\.title) == ["≤ $500.50"])
        viewModel.amount = AmountRange(min: 100, max: 500)
        viewModel.origin = .subscriptions
        #expect(viewModel.activeFilters.map(\.title) == ["$100 – 500", "Subscriptions"])
        viewModel.amount = AmountRange()
        #expect(rows(viewModel).map(\.description) == ["Streaming"])
    }

    @Test
    func theCrossClearsOnlyItsFilter() async {
        let viewModel = await Self.loaded()
        viewModel.amount = AmountRange(min: 10)
        viewModel.origin = .subscriptions
        viewModel.clear(.amount)
        #expect(viewModel.amount.isEmpty)
        #expect(viewModel.origin == .subscriptions)
        viewModel.clear(.origin)
        #expect(viewModel.origin == .any)
        #expect(viewModel.activeFilters.isEmpty)
    }

    @Test
    func openingFromARuleShowsWhatItRecordedUnderItsName() async {
        let viewModel = await Self.loaded()
        viewModel.origin = .rule(IDs.rentRule)
        #expect(rows(viewModel).map(\.description) == ["Rent"])
        #expect(viewModel.activeFilters.map(\.title) == ["Rent"])
        // A deleted rule keeps its movements and says so.
        viewModel.origin = .rule(UUID())
        #expect(viewModel.activeFilters.map(\.title) == ["Deleted rule"])
        #expect(rows(viewModel).isEmpty)
    }

    @Test
    func theSheetAppliesOnlyAValidRange() async {
        let viewModel = await Self.loaded()
        var draft = viewModel.makeFiltersDraft()
        #expect(draft == MoreFiltersDraft())
        draft.minText = "500"
        draft.maxText = "100"
        #expect(draft.isMinAboveMax)
        #expect(!draft.canApply)
        viewModel.apply(draft)
        #expect(viewModel.amount.isEmpty)
        draft.maxText = "1,000"
        draft.origin = .subscriptions
        viewModel.apply(draft)
        #expect(viewModel.amount == AmountRange(min: 500, max: 1000))
        #expect(viewModel.origin == .subscriptions)
        #expect(viewModel.makeFiltersDraft().minText == "500.00")
        draft.minText = "abc"
        #expect(!draft.canApply)
    }

    @Test
    func theConversionNoteNamesThePrincipalWhenThereIsASecondCurrency() async {
        let viewModel = await Self.loaded()
        #expect(viewModel.conversionNote == "Converted to USD at each movement's rate")
    }
}
