import CreditCardDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreditCardPresentation

@MainActor
enum CreditCardFactory {
    static func make(store: InMemoryStore, accountID: UUID = SampleData.IDs.mastercard) -> CreditCardViewModel {
        CreditCardViewModel(
            accountID: accountID,
            getDetail: DefaultGetCreditCardDetailUseCase(
                accounts: store, cards: store, transactions: store, categories: store, settings: store,
                now: { SampleData.defaultReferenceDate },
            ),
            updateTerms: DefaultUpdateCreditTermsUseCase(accounts: store),
            setCardColor: DefaultSetCardColorUseCase(cards: store),
            setCardDetails: DefaultSetCardDetailsUseCase(cards: store),
            setCardNumber: DefaultSetCardNumberUseCase(cards: store),
            renameAccount: DefaultRenameAccountUseCase(accounts: store),
            deleteAccount: DefaultDeleteAccountUseCase(accounts: store, cards: store, transactions: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
        )
    }

    static func loaded(store: InMemoryStore = InMemoryStore(sample: .standard)) async -> CreditCardViewModel {
        let viewModel = make(store: store)
        await viewModel.load()
        return viewModel
    }
}

@Suite("Credit card view model")
@MainActor
struct CreditCardViewModelTests {
    @Test
    func aDualCardShowsEachDebtAndTheTotal() async throws {
        let viewModel = await CreditCardFactory.loaded()
        let detail = try #require(viewModel.detail)
        #expect(viewModel.headline(detail).contains(" · "))
        let total = viewModel.owed(detail.totalDebt)
        #expect(viewModel.totalDebtLine(detail) == "Total \(total)")
    }

    @Test
    func changingTheNumberKeepsTheCard() async {
        let viewModel = await CreditCardFactory.loaded()
        #expect(await viewModel.setHolderNumber(lastFour: "4321", network: .visa))
        #expect(viewModel.detail?.holder?.lastFour == "4321")
        #expect(viewModel.detail?.holder?.network == .visa)
    }

    @Test
    func theDigitsAreRequiredOnACreditCard() async {
        let viewModel = await CreditCardFactory.loaded()
        let before = viewModel.detail?.holder?.lastFour
        #expect(await !viewModel.setHolderNumber(lastFour: "", network: .visa))
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.detail?.holder?.lastFour == before)
    }

    @Test
    func deletingTheCardLeavesNothingToShow() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = await CreditCardFactory.loaded(store: store)
        #expect(await viewModel.delete())
        #expect(viewModel.state == .deleted)
        #expect(await store.fetchAccounts().contains { $0.id == SampleData.IDs.mastercard } == false)
        await viewModel.load()
        #expect(viewModel.state == .deleted)
    }

    @Test
    func theDeleteMessageCountsTheMovements() async throws {
        let viewModel = await CreditCardFactory.loaded()
        let detail = try #require(viewModel.detail)
        #expect(viewModel.deleteMessage(detail).contains("its \(detail.movementCount) movements"))
    }
}
