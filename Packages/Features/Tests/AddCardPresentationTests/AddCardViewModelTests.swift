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
            getContext: DefaultGetAddCardContextUseCase(settings: store),
            addCredit: DefaultAddCreditCardUseCase(accounts: store, cards: store, settings: store),
            addAccount: DefaultAddAccountUseCase(accounts: store, cards: store),
            getPreferredName: DefaultGetPreferredNameUseCase(profile: InMemoryPasscodeStore(name: "Steven")),
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
        viewModel.stepCutoff(by: 1)
        viewModel.stepDue(by: 1)
        await viewModel.addCreditCard()
        #expect(viewModel.path.last == .done)
        #expect(viewModel.createdAccount?.openingBalances == [Money(0, "USD"), Money(-250, "NIO")])
        #expect(viewModel.summary == "Debt in USD and NIO · cutoff day 28 · due day 15. We'll remind you 3 days before the due date.")
    }

    @Test
    func billingDaysAreNotSetByDefault() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = AddCardFactory.make(store: store)
        await viewModel.load()
        viewModel.choose(.credit)
        viewModel.bank = "Bank Three"
        viewModel.lastFour = "2468"
        #expect(viewModel.cutoffDay == nil)
        #expect(viewModel.dueDay == nil)
        await viewModel.addCreditCard()
        #expect(viewModel.createdAccount?.creditTerms?.cutoffDay == nil)
        #expect(viewModel.createdAccount?.creditTerms?.dueDay == nil)
        #expect(viewModel.summary == "Debt in USD and NIO.")
    }

    @Test
    func aDayStartsFromAValueOnceChosen() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.stepCutoff(by: -1)
        #expect(viewModel.cutoffDay == 28)
        viewModel.clearCutoff()
        #expect(viewModel.cutoffDay == nil)
        viewModel.stepDue(by: 1)
        #expect(viewModel.dueDay == 15)
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
    func aDebitCardCreatesItsBankAccount() async {
        let store = InMemoryStore(sample: .standard)
        let viewModel = AddCardFactory.make(store: store)
        await viewModel.load()
        viewModel.choose(.debit)
        viewModel.bank = "Bank Three"
        viewModel.lastFour = "1357"
        #expect(!viewModel.canContinueFromPlastic)
        viewModel.accountName = "Checking"
        viewModel.accountCurrency = "NIO"
        viewModel.balanceText = "1,200"
        await viewModel.continueFromPlastic()
        #expect(viewModel.path == [.plastic, .done])
        let account = viewModel.createdAccount
        #expect(account?.kind == .deposit)
        #expect(account?.openingBalances == [Money(1200, "NIO")])
        let cards = await store.fetchCards().filter { $0.accountID == account?.id && $0.kind == .debit }
        #expect(cards.map(\.lastFour) == ["1357"])
        #expect(viewModel.summary == "Bank Three Checking is ready: this card is the account, with its balance and movements.")
    }

    @Test
    func aDebitCardNeedsABalanceThatReads() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.choose(.debit)
        viewModel.lastFour = "1357"
        viewModel.accountName = "Checking"
        viewModel.balanceText = "abc"
        #expect(!viewModel.canContinueFromPlastic)
        viewModel.balanceText = ""
        #expect(viewModel.canContinueFromPlastic)
    }

    @Test
    func daysWrapAroundTheMonth() async {
        let viewModel = await AddCardFactory.loaded()
        viewModel.stepCutoff(by: 1)
        viewModel.stepCutoff(by: 4)
        #expect(viewModel.cutoffDay == 1)
        viewModel.stepDue(by: 1)
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
    func creatingAWalletChecksTheBalance() async {
        let viewModel = await AddCardFactory.loaded()
        #expect(await viewModel.createWallet(name: "Envelope", currency: "NIO", balanceText: "40"))
        #expect(await !viewModel.createWallet(name: "Envelope", currency: "NIO", balanceText: "abc"))
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
