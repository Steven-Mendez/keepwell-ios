import Domain
import DomainSamples
import Foundation
import Testing
import TransactionsDomain
@testable import TransactionsPresentation

@Suite("Transaction detail view model")
@MainActor
struct TransactionDetailViewModelTests {
    private typealias IDs = SampleData.IDs
    private let now = SampleData.defaultReferenceDate
    private let movementID = UUID(uuidString: "7E1A2B3C-0000-4000-8000-0000000000D1") ?? UUID()

    /// A planned dinner in córdobas from the rent's rule, with a bank charge, a note and a tag.
    private func storeWithMovement(kind: TransactionKind = .expense, status: TransactionStatus = .planned) async -> InMemoryStore {
        let store = InMemoryStore(sample: .standard)
        await store.save(Transaction(
            id: movementID,
            date: now,
            status: status,
            description: "Dinner",
            kind: kind,
            categoryID: kind == .transfer ? nil : (kind == .expense ? "restaurants" : "salary"),
            amount: 732,
            currency: "NIO",
            accountID: IDs.savings,
            cardID: IDs.savingsDebit,
            destinationAccountID: kind == .transfer ? IDs.cash : nil,
            actualDebitedPrincipal: kind == .expense ? 20 : nil,
            exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
            note: "With Ana",
            recurringID: IDs.rentRule,
            tags: ["viaje"],
        ))
        return store
    }

    private func make(store: InMemoryStore, id: UUID? = nil) async -> TransactionDetailViewModel {
        let viewModel = TransactionDetailViewModel(
            transactionID: id ?? movementID,
            getList: DefaultGetTransactionListUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store, recurringRules: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store, now: { [now] in now }),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
        )
        await viewModel.load()
        return viewModel
    }

    @Test
    func showsWhatTheMovementWasAndWhereItWent() async throws {
        let viewModel = await make(store: storeWithMovement())
        let transaction = try #require(viewModel.transaction)
        #expect(transaction.description == "Dinner")
        #expect(viewModel.kindText == "Expense")
        #expect(viewModel.statusText == "Draft")
        #expect(viewModel.routeRows.map(\.label) == ["Category", "Paid with"])
        #expect(viewModel.routeRows.first?.value == "Restaurants")
        #expect(viewModel.reference == "KW-7E1A2B3C")
        #expect(viewModel.recurringRule?.id == IDs.rentRule)
        #expect(viewModel.recurringText != nil)
    }

    @Test
    func theRateCardShowsTheRecordedAndTheBankRate() async {
        let viewModel = await make(store: storeWithMovement())
        #expect(viewModel.rateRows.map(\.label) == ["Rate used", "Bank rate"])
        #expect(viewModel.rateRows.first?.value == "1 USD = 36.6243 NIO")
        #expect(viewModel.rateRows.last?.value == "36.60 NIO")
    }

    @Test
    func aTransferShowsBothEndsAndCantBeSplit() async {
        let viewModel = await make(store: storeWithMovement(kind: .transfer))
        #expect(viewModel.kindText == "Transfer")
        #expect(viewModel.routeRows.map(\.label) == ["From", "To"])
        #expect(viewModel.routeRows.last?.value == "Wallet")
        #expect(!viewModel.canSplit)
    }

    @Test
    func onlyExpensesSplitAndOnlyDraftsConfirm() async {
        let draft = await make(store: storeWithMovement())
        #expect(draft.canSplit)
        #expect(draft.canConfirm)
        let income = await make(store: storeWithMovement(kind: .income, status: .confirmed))
        #expect(!income.canSplit)
        #expect(!income.canConfirm)
        #expect(income.statusText == "Confirmed")
        #expect(income.routeRows.map(\.label) == ["Category", "Into"])
    }

    @Test
    func confirmingADraftCountsItAndReloads() async {
        let viewModel = await make(store: storeWithMovement())
        await viewModel.confirm()
        #expect(viewModel.transaction?.isConfirmed == true)
        #expect(!viewModel.canConfirm)
        #expect(viewModel.actionError == nil)
    }

    @Test
    func deletingRemovesItAndAsksToClose() async {
        let store = await storeWithMovement()
        let viewModel = await make(store: store)
        await viewModel.delete()
        #expect(viewModel.isDeleted)
        #expect(await store.fetchTransactions(in: nil).contains { $0.id == movementID } == false)
        await viewModel.load()
        #expect(viewModel.state == .missing)
    }

    @Test
    func aMovementThatIsGoneReadsAsMissing() async {
        let viewModel = await make(store: InMemoryStore(sample: .standard), id: UUID())
        #expect(viewModel.state == .missing)
        #expect(viewModel.transaction == nil)
    }

    @Test
    func aTagFromTheDetailNarrowsTheWholeList() async {
        let store = await storeWithMovement(status: .confirmed)
        let list = TransactionsViewModel(
            getList: DefaultGetTransactionListUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store,
            ),
            confirmPlanned: DefaultConfirmPlannedTransactionUseCase(transactions: store),
            deleteTransaction: DefaultDeleteTransactionUseCase(transactions: store),
            now: { [now] in now },
        )
        await list.load()
        list.scope = .account(IDs.cash)
        list.filter = .income
        list.showOnly(tag: "viaje")
        #expect(list.scope == .all)
        #expect(list.filter == .all)
        #expect(list.query == "#viaje")
        let rows = list.sections.flatMap(\.transactions)
        #expect(rows.contains { $0.id == movementID })
        #expect(rows.allSatisfy { $0.tags.contains("viaje") })
    }
}
