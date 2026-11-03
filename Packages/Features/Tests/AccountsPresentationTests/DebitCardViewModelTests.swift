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
            accountID: SampleData.IDs.savings,
            getDetail: DefaultGetDebitCardDetailUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
            ),
            setColor: DefaultSetCardColorUseCase(cards: store),
            setDetails: DefaultSetCardDetailsUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
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
        #expect(viewModel.balance(detail).hasPrefix("$"))
        #expect(viewModel.subtitle(detail) == "Bank account · USD")
        #expect(viewModel.deleteTitle(detail) == "Delete Bank One Savings?")
        #expect(viewModel.deleteMessage(detail).contains("its \(detail.movementCount) movements"))
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
    func deletingTheAccountLeavesNothingToShow() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await DebitCardFactory.loaded(store: store)
        #expect(await viewModel.delete())
        #expect(viewModel.state == .deleted)
        #expect(await store.fetchAccounts().contains { $0.id == SampleData.IDs.savings } == false)
        #expect(await store.fetchCards().contains { $0.id == SampleData.IDs.savingsDebit } == false)
        // A reload after the screen closes must not turn the deleted account into an error.
        await viewModel.load()
        #expect(viewModel.state == .deleted)
    }

    @Test
    func anAccountWithNoMovementsSaysOnlyTheCardGoes() throws {
        let account = Account(name: "New", kind: .deposit, openingBalances: [Money(0, "USD")], openingDate: .now)
        let detail = try DebitCardDetail(card: Card.debit(for: account.id), account: account, balance: Money(0, "USD"))
        let viewModel = DebitCardFactory.make()
        #expect(viewModel.deleteMessage(detail) == "The account and its card are deleted. This can't be undone.")
    }

    @Test
    func aMissingCardFailsToLoad() async {
        let store = InMemoryStore(sample: .standard)
        try? await store.deleteCard(id: SampleData.IDs.savingsDebit)
        let viewModel = await DebitCardFactory.loaded(store: store)
        #expect(viewModel.state == .failed)
    }
}
