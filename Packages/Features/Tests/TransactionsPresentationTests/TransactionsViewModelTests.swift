import Domain
import DomainSamples
import Foundation
import Testing
import TransactionsDomain
@testable import TransactionsPresentation

@Suite("Transactions view model")
@MainActor
struct TransactionsViewModelTests {
    private typealias IDs = SampleData.IDs

    private func loaded() async -> TransactionsViewModel {
        let store = InMemoryStore(sample: .standard)
        let viewModel = TransactionsViewModel(
            getList: DefaultGetTransactionListUseCase(
                transactions: store, accounts: store, cards: store, categories: store, settings: store,
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
    func anAccountFilterNarrowsTheRowsAndNamesTheAccount() async {
        let viewModel = await loaded()
        viewModel.scope = .account(IDs.cash)
        #expect(!rows(viewModel).isEmpty)
        #expect(rows(viewModel).allSatisfy { $0.accountID == IDs.cash || $0.destinationAccountID == IDs.cash })
        #expect(viewModel.scopeTitle == "Wallet")
        #expect(viewModel.scopeBalance?.label == "Available balance")
        // Cash in córdobas keeps its own currency instead of a converted total.
        #expect(viewModel.scopeBalance?.amount.hasPrefix("C$") == true)
        #expect(viewModel.scopeBalance?.details.isEmpty == true)
    }

    @Test
    func aCardFilterReadsAsTheCard() async {
        let viewModel = await loaded()
        viewModel.scope = .card(IDs.savingsDebit)
        #expect(viewModel.scopeTitle == "Debit •••• 1234")
        #expect(rows(viewModel).allSatisfy { $0.cardID == IDs.savingsDebit })
        viewModel.scope = .account(IDs.mastercard)
        #expect(viewModel.scopeBalance?.label == "Current debt")
        // Owed reads positive, with each currency of the dual card under the total.
        #expect(viewModel.scopeBalance?.amount.hasPrefix("$") == true)
        #expect(viewModel.scopeBalance?.details.count == 2)
    }

    @Test
    func theMonthTotalsFollowTheAccountFilterButNotTheKindChips() async throws {
        let viewModel = await loaded()
        let everything = try #require(viewModel.monthTotals)
        viewModel.scope = .account(IDs.cash)
        let cash = try #require(viewModel.monthTotals)
        #expect(cash.spent != everything.spent || cash.earned != everything.earned)
        viewModel.filter = .income
        #expect(viewModel.monthTotals?.spent == cash.spent)
        #expect(viewModel.monthTotals?.earned == cash.earned)
    }

    @Test
    func searchWorksInsideTheFilter() async {
        let viewModel = await loaded()
        viewModel.scope = .account(IDs.cash)
        viewModel.query = "bus"
        #expect(rows(viewModel).map(\.description) == ["Bus"])
        viewModel.scope = .account(IDs.mastercard)
        #expect(rows(viewModel).isEmpty)
        #expect(!viewModel.isScopeEmpty)
    }

    @Test
    func withoutAFilterThereIsNoBalanceHeader() async {
        let viewModel = await loaded()
        #expect(viewModel.scopeTitle == "All accounts")
        #expect(viewModel.scopeBalance == nil)
    }
}
