import FeatureTestSupport
import OnboardingDomain
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Accounts snapshots")
@MainActor
struct AccountsSnapshotTests {
    private func viewModelWithAccounts() -> OnboardingViewModel {
        let viewModel = OnboardingFactory.make()
        var cash = viewModel.newAccount(.cash)
        cash.balance = 560
        viewModel.save(cash)
        var bank = viewModel.newAccount(.bank)
        bank.bank = "Banco Uno"
        bank.name = "Ahorro"
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
        let viewModel = OnboardingFactory.make()
        let form = AccountFormView(
            draft: viewModel.newAccount(.credit), principal: "USD", second: "NIO", isNew: true,
            onSave: { _ in }, onRemove: {}, onClose: {},
        )
        assertScreenSnapshot(of: form)
    }

    @Test
    func initials() {
        #expect(AccountsView.initials("Banco Uno") == "BU")
        #expect(AccountsView.initials("Lafise") == "LA")
    }

    @Test
    func amountParsing() {
        #expect(AccountFormView.amount("") == 0)
        #expect(AccountFormView.amount("9,443.6") == Decimal(string: "9443.6"))
        #expect(AccountFormView.amount("12,5") == Decimal(string: "12.5"))
        #expect(AccountFormView.amount("-1") == nil)
    }
}
