import AccountsDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsPresentation

@MainActor
enum AccountsFactory {
    static func make(store: InMemoryStore = InMemoryStore(sample: .standard)) -> AccountsViewModel {
        AccountsViewModel(
            getOverview: DefaultGetAccountsOverviewUseCase(accounts: store, cards: store, transactions: store, settings: store),
            reconcileCash: DefaultReconcileCashUseCase(transactions: store, settings: store),
            withdrawCash: DefaultWithdrawCashUseCase(transactions: store, cards: store, settings: store),
        )
    }

    static func loaded() async -> AccountsViewModel {
        let viewModel = make()
        await viewModel.load()
        return viewModel
    }
}

@Suite("Accounts view model")
@MainActor
struct AccountsViewModelTests {
    @Test
    func loadsTheOverview() async {
        let viewModel = await AccountsFactory.loaded()
        #expect(viewModel.overview?.deposits.count == 2)
    }

    @Test
    func reconcilingUpdatesTheCashBalance() async throws {
        let viewModel = await AccountsFactory.loaded()
        let cash = try #require(viewModel.overview?.cash.first)
        #expect(await viewModel.reconcile(cash, countedText: "8,000"))
        #expect(viewModel.overview?.cash.first?.balance == Money(8000, "NIO"))
    }

    @Test
    func reconcilingRejectsInvalidText() async throws {
        let viewModel = await AccountsFactory.loaded()
        let cash = try #require(viewModel.overview?.cash.first)
        #expect(await !viewModel.reconcile(cash, countedText: "abc"))
        #expect(viewModel.actionError != nil)
        viewModel.clearActionError()
        #expect(viewModel.actionError == nil)
    }

    @Test
    func withdrawingMovesMoneyIntoCash() async throws {
        let viewModel = await AccountsFactory.loaded()
        let cash = try #require(viewModel.overview?.cash.first)
        #expect(await viewModel.withdraw(into: cash, from: SampleData.IDs.savings, amountText: "1000", debitedText: "27.50"))
        #expect(viewModel.overview?.cash.first?.balance == Money(9390, "NIO"))
    }

    @Test
    func withdrawingRejectsBadDebit() async throws {
        let viewModel = await AccountsFactory.loaded()
        let cash = try #require(viewModel.overview?.cash.first)
        #expect(await !viewModel.withdraw(into: cash, from: SampleData.IDs.savings, amountText: "1000", debitedText: "x"))
        #expect(await !viewModel.withdraw(into: cash, from: SampleData.IDs.savings, amountText: "", debitedText: ""))
    }
}
