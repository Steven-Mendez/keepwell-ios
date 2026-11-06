import AddCardDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import AddCardPresentation

@MainActor
enum AddCardFactory {
    static func make(store: InMemoryStore = InMemoryStore(sample: .standard)) -> AddCardViewModel {
        AddCardViewModel(
            getContext: DefaultGetAddCardContextUseCase(settings: store, accounts: store),
            addCredit: DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store),
            addDebit: DefaultAddDebitCardUseCase(accounts: store, cards: store),
            addAccount: DefaultAddAccountUseCase(accounts: store, cards: store),
        )
    }

    static func loaded() async -> AddCardViewModel {
        let viewModel = make()
        await viewModel.load()
        return viewModel
    }
}

@Suite("Add card view model")
@MainActor
struct AddCardViewModelTests {
    @Test
    func creditFlowGoesThroughDebtAndSaves() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = AddCardFactory.make(store: store)
        await viewModel.load()
        viewModel.choose(.credit)
        viewModel.bank = "Bank Three"
        viewModel.lastFour = "2468"
        await viewModel.continueFromPlastic()
        #expect(viewModel.path == [.plastic, .debt])
        viewModel.secondDebtText = "250"
        await viewModel.addCreditCard()
        #expect(viewModel.path.last == .done)
        #expect(viewModel.createdAccount?.openingBalances == [Money(0, "USD"), Money(-250, "NIO")])
        #expect(viewModel.summary == "Debt in USD and NIO · cutoff day 28 · due day 15. We'll remind you 3 days before the due date.")
    }

    @Test
    func lastFourMustBeFourDigits() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.credit)
        viewModel.lastFour = "12a4"
        #expect(!viewModel.canContinueFromPlastic)
        await viewModel.continueFromPlastic()
        #expect(viewModel.path == [.plastic])
    }

    @Test
    func debitCardSavesFromThePlasticStep() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.debit, linkingTo: SampleData.IDs.payroll)
        viewModel.lastFour = "1357"
        await viewModel.continueFromPlastic()
        #expect(viewModel.path == [.plastic, .done])
        #expect(viewModel.createdCard?.accountID == SampleData.IDs.payroll)
        #expect(viewModel.summary == "Linked to Bank Two Payroll.")
    }

    @Test
    func daysWrapAroundTheMonth() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.stepCutoff(by: 4)
        #expect(viewModel.cutoffDay == 1)
        viewModel.stepDue(by: -15)
        #expect(viewModel.dueDay == 31)
    }

    @Test
    func invalidAmountsBlockAdding() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.limitText = "0"
        #expect(!viewModel.canAddCreditCard)
        viewModel.limitText = "1,500"
        viewModel.principalDebtText = "x"
        #expect(!viewModel.canAddCreditCard)
    }

    @Test
    func modeCopyFollowsTheCurrencies() async {
        let viewModel = await AddCardFactory.loaded()
        #expect(viewModel.modeTitle(.dual) == "Two currencies")
        #expect(viewModel.modeSubtitle(.dual) == "USD and NIO, paid separately")
        #expect(viewModel.modeTitle(.second) == "Only NIO")
        #expect(viewModel.modeSubtitle(.principal) == "Everything is converted to dollars")
    }

    @Test
    func creatingAWalletReloadsTheContext() async {
        let viewModel = await AddCardFactory.loaded()
        #expect(await viewModel.createAccount(kind: .deposit, name: "Checking", bank: "Bank Three", currency: "USD", balanceText: "40"))
        #expect(viewModel.context?.depositAccounts.count == 3)
        #expect(await !viewModel.createAccount(kind: .cash, name: "Envelope", bank: nil, currency: "NIO", balanceText: "abc"))
    }

    @Test
    func restartClearsTheForm() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.credit)
        viewModel.lastFour = "2468"
        viewModel.restart()
        #expect(viewModel.path.isEmpty)
        #expect(viewModel.lastFour.isEmpty)
    }
}
