import FeatureTestSupport
import OnboardingDomain
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Accounts snapshots")
@MainActor
struct AccountsSnapshotTests {
    private func viewModelWithAccounts() -> OnboardingViewModel {
        let viewModel = OnboardingFactory.usdAndNIO()
        var cash = viewModel.accounts[0]
        cash.balance = 560
        viewModel.save(cash)
        var bank = viewModel.newAccount(.bank)
        bank.bank = "Bank One"
        bank.name = "Savings"
        bank.balance = 9443.6
        bank.lastFour = "1234"
        viewModel.save(bank)
        var credit = viewModel.newAccount(.credit)
        credit.name = "Mastercard ··4321"
        viewModel.save(credit)
        return viewModel
    }

    @Test
    func listsCashBankAndCredit() {
        assertScreenSnapshot(of: AccountsView(viewModel: viewModelWithAccounts(), onBack: {}, onImportCSV: {}))
    }

    @Test
    func creditCardForm() {
        let viewModel = OnboardingFactory.usdAndNIO()
        let form = AccountFormView(
            draft: viewModel.newAccount(.credit), principal: "USD", second: "NIO", isNew: true,
            onSave: { _ in }, onRemove: {}, onClose: {},
        )
        assertScreenSnapshot(of: form)
    }

    @Test
    func initials() {
        #expect(AccountsView.initials("Bank One") == "BO")
        #expect(AccountsView.initials("Lafise") == "LA")
    }

    @Test
    func amountParsing() {
        #expect(AccountFormView.amount("") == 0)
        #expect(AccountFormView.amount("9,443.6") == Decimal(string: "9443.6"))
        #expect(AccountFormView.amount("12,5") == Decimal(string: "12.5"))
        #expect(AccountFormView.amount("-1") == nil)
    }

    @Test
    func bankAccountForm() {
        let viewModel = OnboardingFactory.make()
        var draft = viewModel.newAccount(.bank)
        draft.bank = "LAFISE"
        draft.name = "Savings"
        draft.lastFour = "1234"
        draft.balance = 10000
        let form = AccountFormView(
            draft: draft, principal: "USD", second: "NIO", isNew: false,
            onSave: { _ in }, onRemove: {}, onClose: {},
        )
        assertScreenSnapshot(of: form)
    }

    @Test
    func validationPointsAtTheFirstProblem() {
        #expect(AccountFormView.problem(lastFour: nil, balance: "10,000.00", secondBalance: "") == nil)
        #expect(AccountFormView.problem(lastFour: "12", balance: "", secondBalance: "") == .incompleteLastFour)
        #expect(AccountFormView.problem(lastFour: "1234", balance: "1.2.3", secondBalance: "") == .invalidAmount)
        #expect(AccountFormView.problem(lastFour: nil, balance: "", secondBalance: "abc") == .invalidSecondAmount)
    }

    @Test
    func eachProblemBelongsToItsField() {
        #expect(AccountFormView.Problem.incompleteLastFour.field == .lastFour)
        #expect(AccountFormView.Problem.invalidAmount.field == .balance)
        #expect(AccountFormView.Problem.invalidSecondAmount.field == .secondBalance)
    }
}
