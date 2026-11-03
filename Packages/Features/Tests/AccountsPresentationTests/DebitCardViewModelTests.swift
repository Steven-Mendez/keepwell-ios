import AccountsDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import AccountsPresentation

@MainActor
enum DebitCardFactory {
    static func make(store: InMemoryStore = InMemoryStore(sample: .standard)) -> DebitCardViewModel {
        DebitCardViewModel(
            cardID: SampleData.IDs.savingsDebit,
            getDetail: DefaultGetDebitCardDetailUseCase(accounts: store, cards: store, transactions: store, settings: store),
            setFrozen: DefaultSetCardFrozenUseCase(cards: store),
            setColor: DefaultSetCardColorUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            removeCard: DefaultRemoveCardUseCase(cards: store),
        )
    }

    static func loaded(store: InMemoryStore = InMemoryStore(sample: .standard)) async -> DebitCardViewModel {
        let viewModel = make(store: store)
        await viewModel.load()
        return viewModel
    }
}

@Suite("Debit card view model")
@MainActor
struct DebitCardViewModelTests {
    @Test
    func loadsTheCard() async throws {
        let viewModel = await DebitCardFactory.loaded()
        let detail = try #require(viewModel.detail)
        #expect(detail.account.name == "Savings")
        #expect(viewModel.bank(detail) == "Bank One")
        #expect(viewModel.subtitle(detail).hasPrefix("Balance $"))
    }

    @Test
    func freezingTogglesAndReloads() async {
        let viewModel = await DebitCardFactory.loaded()
        await viewModel.toggleFrozen()
        #expect(viewModel.detail?.card.isFrozen == true)
        await viewModel.toggleFrozen()
        #expect(viewModel.detail?.card.isFrozen == false)
    }

    @Test
    func changingTheColorShowsTheNewArt() async {
        let viewModel = await DebitCardFactory.loaded()
        #expect(await viewModel.setColor(.verde))
        #expect(viewModel.detail?.card.color == .verde)
    }

    @Test
    func renamingTheAccount() async {
        let viewModel = await DebitCardFactory.loaded()
        #expect(await viewModel.rename(to: "Travel"))
        #expect(viewModel.detail?.account.name == "Travel")
    }

    @Test
    func anEmptyNameAsksForOne() async {
        let viewModel = await DebitCardFactory.loaded()
        #expect(await !viewModel.rename(to: " "))
        #expect(viewModel.errorMessage == "Write a name for the account.")
        #expect(viewModel.detail?.account.name == "Savings")
        viewModel.clearError()
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func removingLeavesNothingToShow() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await DebitCardFactory.loaded(store: store)
        #expect(await viewModel.remove())
        #expect(viewModel.state == .removed)
        #expect(await store.fetchCards().contains { $0.id == SampleData.IDs.savingsDebit } == false)
        // A reload after the screen closes must not turn the removed card into an error.
        await viewModel.load()
        #expect(viewModel.state == .removed)
    }

    @Test
    func aMissingCardFailsToLoad() async {
        let store = InMemoryStore(sample: .standard)
        try? await store.deleteCard(id: SampleData.IDs.savingsDebit)
        let viewModel = await DebitCardFactory.loaded(store: store)
        #expect(viewModel.state == .failed)
    }
}
