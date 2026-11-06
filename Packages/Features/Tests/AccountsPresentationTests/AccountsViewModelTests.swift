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
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
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
        #expect(viewModel.overview != nil)
    }

    @Test
    func theWalletHoldsEveryCardWithCashInFront() async throws {
        let viewModel = await AccountsFactory.loaded()
        let overview = try #require(viewModel.overview)
        #expect(viewModel.cards.count == overview.deposits.count + overview.creditCards.count + overview.cash.count)
        #expect(viewModel.cards.last.map {
            if case .cash = $0 {
                true
            } else {
                false
            }
        } == true)
    }

    @Test
    func chipsShowOneKindAtATime() async {
        let viewModel = await AccountsFactory.loaded()
        #expect(viewModel.filters == [.all, .debit, .credit, .cash])
        viewModel.filter = .credit
        #expect(viewModel.cards.allSatisfy {
            if case .credit = $0 {
                true
            } else {
                false
            }
        })
        #expect(!viewModel.cards.isEmpty)
        viewModel.filter = .cash
        #expect(viewModel.cards.count == viewModel.overview?.cash.count)
    }
}
