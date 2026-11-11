import AccountsDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsPresentation

@MainActor
enum CashFactory {
    static func loaded(store: InMemoryStore = InMemoryStore(sample: .standard)) async -> CashViewModel {
        let viewModel = CashViewModel(
            accountID: SampleData.IDs.cash,
            getDetail: DefaultGetCashDetailUseCase(accounts: store, cards: store, transactions: store, categories: store, settings: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store),
        )
        await viewModel.load()
        return viewModel
    }
}

@Suite("Cash view model")
@MainActor
struct CashViewModelTests {
    @Test
    func loadsTheAccount() async throws {
        let viewModel = await CashFactory.loaded()
        let detail = try #require(viewModel.detail)
        #expect(viewModel.balance(detail).isEmpty == false)
        #expect(viewModel.deleteTitle(detail) == "Delete \(detail.account.name)?")
        #expect(viewModel.deleteMessage(detail).contains("its \(detail.movementCount) movements"))
    }

    @Test
    func renamingTheAccount() async {
        let viewModel = await CashFactory.loaded()
        #expect(await viewModel.rename(to: "Wallet"))
        #expect(viewModel.detail?.account.name == "Wallet")
    }

    @Test
    func anEmptyNameAsksForOne() async {
        let viewModel = await CashFactory.loaded()
        let name = viewModel.detail?.account.name
        #expect(await !viewModel.rename(to: " "))
        #expect(viewModel.errorMessage == "Write a name for the account.")
        #expect(viewModel.detail?.account.name == name)
    }

    @Test
    func deletingTheAccountLeavesNothingToShow() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await CashFactory.loaded(store: store)
        #expect(await viewModel.delete())
        #expect(viewModel.state == .deleted)
        #expect(await store.fetchAccounts().contains { $0.id == SampleData.IDs.cash } == false)
        await viewModel.load()
        #expect(viewModel.state == .deleted)
    }
}
