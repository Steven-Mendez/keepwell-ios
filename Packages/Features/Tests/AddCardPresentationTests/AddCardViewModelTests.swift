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
        viewModel.bank = "Banco Tres"
        viewModel.lastFour = "2468"
        await viewModel.continueFromPlastic()
        #expect(viewModel.path == [.plastic, .debt])
        viewModel.secondDebtText = "250"
        await viewModel.addCreditCard()
        #expect(viewModel.path.last == .done)
        #expect(viewModel.createdAccount?.openingBalances == [Money(0, "USD"), Money(-250, "NIO")])
        #expect(viewModel.summary == "Deuda en USD y NIO · corte día 28 · pago día 15. Te avisamos 3 días antes del pago.")
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
        #expect(viewModel.summary == "Vinculada a Banco Dos Nómina.")
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
        #expect(viewModel.modeTitle(.dual) == "Dos monedas")
        #expect(viewModel.modeSubtitle(.dual) == "USD y NIO por separado, se pagan aparte")
        #expect(viewModel.modeTitle(.second) == "Solo NIO")
        #expect(viewModel.modeSubtitle(.principal) == "Todo se convierte a dólares")
    }

    @Test
    func creatingAWalletReloadsTheContext() async {
        let viewModel = await AddCardFactory.loaded()
        #expect(await viewModel.createAccount(kind: .deposit, name: "Corriente", bank: "Banco Tres", currency: "USD", balanceText: "40"))
        #expect(viewModel.context?.depositAccounts.count == 3)
        #expect(await !viewModel.createAccount(kind: .cash, name: "Sobre", bank: nil, currency: "NIO", balanceText: "abc"))
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
