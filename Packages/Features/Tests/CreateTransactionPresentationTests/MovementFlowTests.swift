import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionPresentation

@Suite("Movement flow")
@MainActor
struct MovementFlowTests {
    private func type(_ viewModel: CreateTransactionViewModel, _ digits: String) {
        for character in digits {
            if character == "." {
                viewModel.press(.dot)
            } else if let digit = character.wholeNumberValue {
                viewModel.press(.digit(digit))
            }
        }
    }

    // MARK: Steps

    @Test
    func expensesStartAtTheAmountAndTransfersAtTheAccounts() async {
        let expense = await CreateTransactionFactory.loaded()
        #expect(expense.rootStep == .amount)
        #expect(expense.progress(of: .amount) == (4, 1))
        #expect(expense.progress(of: .review) == (4, 4))
        let transfer = await CreateTransactionFactory.loaded(.transfer)
        #expect(transfer.rootStep == .accounts)
        #expect(transfer.progress(of: .amount) == (3, 2))
        #expect(transfer.amountButtonTitle == "Review")
    }

    @Test
    func continueStaysDisabledUntilBothAccountsAndAnAmountAreThere() async {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        #expect(viewModel.sourceAccount != nil)
        #expect(viewModel.destinationAccountID == nil)
        #expect(!viewModel.canContinueFromAccounts)
        viewModel.continueFromAccounts()
        #expect(viewModel.path.isEmpty)

        viewModel.selectDestination(SampleData.IDs.cash)
        #expect(viewModel.canContinueFromAccounts)
        viewModel.continueFromAccounts()
        #expect(viewModel.path == [.amount])
        #expect(!viewModel.canContinueFromAmount)
        type(viewModel, "100")
        viewModel.continueFromAmount()
        #expect(viewModel.path == [.amount, .review])
    }

    @Test
    func transfersOfferOnlyOwnAccountsAndNeverTheSourceAsDestination() async throws {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        #expect(viewModel.sourceOptions.allSatisfy { $0.kind != .credit })
        let source = try #require(viewModel.sourceAccount)
        #expect(!viewModel.destinationOptions.contains { $0.id == source.id })
        #expect(viewModel.destinationOptions.allSatisfy { $0.kind != .credit })
    }

    @Test
    func choosingTheDestinationAsSourceClearsItAndUsesTheAccountsCurrency() async {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        viewModel.selectSourceAccount(SampleData.IDs.savings)
        #expect(viewModel.source == .card(SampleData.IDs.savingsTransfer))
        #expect(viewModel.currency == "USD")
        viewModel.selectDestination(SampleData.IDs.cash)
        viewModel.selectSourceAccount(SampleData.IDs.cash)
        #expect(viewModel.source == .account(SampleData.IDs.cash))
        #expect(viewModel.destinationAccountID == nil)
        #expect(viewModel.currency == "NIO")
    }

    @Test
    func withdrawalsGoFromABankAccountIntoTheOnlyCash() async {
        let viewModel = await CreateTransactionFactory.loaded(.withdrawal)
        #expect(viewModel.sourceOptions.allSatisfy { $0.kind == .deposit })
        #expect(viewModel.destinationAccountID == SampleData.IDs.cash)
        #expect(viewModel.canContinueFromAccounts)
    }

    @Test
    func payingACardStartsWithThatCardChosen() async {
        let viewModel = CreateTransactionFactory.make(type: .transfer)
        viewModel.presetTransfer(to: SampleData.IDs.visa)
        await viewModel.load()
        #expect(viewModel.type == .cardPayment)
        #expect(viewModel.destinationAccountID == SampleData.IDs.visa)
        #expect(viewModel.destinationOptions.map(\.id).contains(SampleData.IDs.mastercard))
        #expect(viewModel.sourceAccount?.kind != .credit)
    }

    // MARK: Amount

    @Test
    func theAmountStepShowsWhatTheSourceHasAndWarnsAboveIt() async throws {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        viewModel.selectSourceAccount(SampleData.IDs.cash)
        let available = try #require(viewModel.context?.balances[SampleData.IDs.cash]?.first)
        #expect(viewModel.availableLabel == "Available \(viewModel.formatter.string(available))")
        type(viewModel, "1")
        #expect(!viewModel.exceedsAvailable)
        type(viewModel, "0000000")
        #expect(viewModel.exceedsAvailable)
    }

    @Test
    func crossCurrencyTransfersSayWhatArrives() async {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        viewModel.selectSourceAccount(SampleData.IDs.savings)
        viewModel.selectDestination(SampleData.IDs.cash)
        type(viewModel, "100")
        #expect(viewModel.conversionLine == "Arrives as C$3,662.43 · 1 USD = 36.6243 NIO")
        #expect(viewModel.arrivedRow?.value == "+C$3,662.43")
        viewModel.selectDestination(SampleData.IDs.payroll)
        #expect(viewModel.conversionLine == nil)
        #expect(viewModel.arrivedRow == nil)
    }

    @Test
    func theNotePillShowsTheNoteOnceWritten() async {
        let viewModel = await CreateTransactionFactory.loaded()
        #expect(viewModel.notePillTitle == "Add a note")
        viewModel.note = "  Dinner with Ana "
        #expect(viewModel.notePillTitle == "Dinner with Ana")
    }

    // MARK: Review

    @Test
    func theReviewShowsWhatIsLeftAndWhereItLands() async throws {
        let viewModel = await CreateTransactionFactory.loaded(.transfer)
        viewModel.selectSourceAccount(SampleData.IDs.savings)
        viewModel.selectDestination(SampleData.IDs.payroll)
        type(viewModel, "100")
        let savings = try #require(viewModel.context?.balances[SampleData.IDs.savings]?.first)
        let payroll = try #require(viewModel.context?.balances[SampleData.IDs.payroll]?.first)
        let left = viewModel.formatter.string(Money(savings.amount - 100, "USD"))
        let landed = viewModel.formatter.string(Money(payroll.amount + 100, "USD"))
        #expect(viewModel.fromParty?.caption == "From")
        #expect(viewModel.fromParty?.detail == "Balance after \(left)")
        #expect(viewModel.toParty?.detail == "Balance after \(landed)")
        viewModel.isPlanned = true
        #expect(viewModel.fromParty?.detail == "Balance \(viewModel.formatter.string(savings))")
        #expect(viewModel.confirmTitle == "Slide to save as planned")
    }

    @Test
    func editingFromTheReviewGoesBackToThatStep() async {
        let expense = await CreateTransactionFactory.loaded()
        type(expense, "12")
        expense.continueFromAmount()
        expense.selectCategory("restaurants")
        expense.selectSource(.card(SampleData.IDs.savingsDebit))
        expense.editSource()
        #expect(expense.path == [.category, .method])
        expense.editCategory()
        #expect(expense.path == [.category])
        expense.editAmount()
        #expect(expense.path.isEmpty)

        let transfer = await CreateTransactionFactory.loaded(.withdrawal)
        transfer.continueFromAccounts()
        type(transfer, "5")
        transfer.continueFromAmount()
        transfer.editAmount()
        #expect(transfer.path == [.amount])
        transfer.editSource()
        #expect(transfer.path.isEmpty)
    }

    // MARK: Saving and the receipt

    @Test
    func aWithdrawalSavesAsATransferIntoCashWithItsOwnDescription() async throws {
        let viewModel = await CreateTransactionFactory.loaded(.withdrawal)
        viewModel.selectSourceAccount(SampleData.IDs.savings)
        viewModel.continueFromAccounts()
        type(viewModel, "40")
        viewModel.note = "Weekend"
        viewModel.continueFromAmount()
        await viewModel.save()
        let saved = try #require(viewModel.saved)
        #expect(saved.transaction.kind == .transfer)
        #expect(saved.transaction.destinationAccountID == SampleData.IDs.cash)
        #expect(saved.transaction.cardID == SampleData.IDs.savingsTransfer)
        #expect(saved.transaction.description == "ATM withdrawal")
        #expect(viewModel.path.last == .saved)
        #expect(viewModel.receiptHeadline == "You withdrew")
    }

    @Test
    func theReceiptTextCarriesTheEssentialsAndAReference() async throws {
        let viewModel = await CreateTransactionFactory.loaded()
        type(viewModel, "879")
        viewModel.continueFromAmount()
        viewModel.selectCategory("restaurants")
        viewModel.selectSource(.card(SampleData.IDs.savingsDebit))
        viewModel.note = "Pollo"
        await viewModel.save()
        let saved = try #require(viewModel.saved)
        let reference = viewModel.reference(saved)
        #expect(reference.hasPrefix("KW-"))
        #expect(reference.count == 11)
        let text = viewModel.receiptText(saved)
        #expect(text.contains("You spent C$879.00"))
        #expect(text.contains("Category: Restaurants"))
        #expect(text.contains("Note: Pollo"))
        #expect(text.contains("Reference: \(reference)"))
    }

    // MARK: Entry sheet

    @Test
    func theMenuOffersEveryTypeTheAccountsAllow() async {
        let store = InMemoryStore(sample: .standard)
        let menu = NewMovementMenuViewModel(getContext: DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        ))
        await menu.load()
        #expect(menu.options.map(\.type) == [.expense, .income, .transfer, .withdrawal, .cardPayment])
        #expect(menu.options.map(\.title) == ["Expense", "Income", "Between my accounts", "ATM withdrawal", "Card payment"])
    }
}
