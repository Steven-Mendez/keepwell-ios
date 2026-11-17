import DebtsDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import DebtsPresentation

@MainActor
@Suite("Debts screens")
struct DebtsViewModelTests {
    private let now = SampleData.defaultReferenceDate
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func loaded(_ store: InMemoryStore = InMemoryStore(sample: .standard)) async -> DebtsViewModel {
        let viewModel = DebtsViewModel(useCases: DebtsPreview.useCases(store: store, now: now), calendar: calendar, now: { [now] in now })
        await viewModel.load()
        return viewModel
    }

    @Test
    func theTotalsShowOneAmountPerCurrencyAndMask() async throws {
        let viewModel = await loaded()
        let totals = try #require(viewModel.overview?.totals)
        #expect(viewModel.totals(totals.youOwe, hidden: false) == "C$55,000.00 · $40.00")
        #expect(viewModel.totals(totals.youOwe, hidden: true) == "•••• · ••••")
        #expect(viewModel.totals([], hidden: false) == "Nothing")
    }

    @Test
    func aLoanRowSaysWhichInstallmentIsNext() async throws {
        let viewModel = await loaded()
        let loan = try #require(viewModel.overview?.loans.first)
        #expect(viewModel.loanLine(loan, hidden: false) == "Next: 3/12 on Oct 28, 2026 · C$5,500.00")
        #expect(viewModel.loanLeft(loan, hidden: false) == "C$55,000.00 left")
    }

    @Test
    func payingFromTheDetailMarksTheNextInstallment() async throws {
        let viewModel = await loaded()
        viewModel.openLoan(SampleData.IDs.motorbikeLoan)
        let detail = try #require(viewModel.loanDetail)
        await detail.load()
        #expect(detail.method != nil)
        #expect(detail.categoryID == TransactionCategory.loanPaymentsID)
        #expect(detail.payTitle == "Pay 3/12 · C$5,500.00")
        await detail.pay()
        #expect(detail.didChange)
        #expect(detail.loan.paidCount == 3)
        #expect(detail.summary(hidden: false) == "3 of 12 paid · C$49,500.00 left")
    }

    @Test
    func installmentsGoToOtherOnceLoanPaymentsIsDeleted() async throws {
        let store = InMemoryStore(sample: .standard)
        await store.deleteCategory(id: TransactionCategory.loanPaymentsID)
        let viewModel = await loaded(store)
        viewModel.openLoan(SampleData.IDs.motorbikeLoan)
        let detail = try #require(viewModel.loanDetail)
        await detail.load()
        #expect(detail.categoryID == TransactionCategory.otherExpenseID)
    }

    @Test
    func aNewDebtIsSavedAndListedFirst() async throws {
        let viewModel = await loaded()
        viewModel.newDebt(.iOwe)
        let editor = try #require(viewModel.debtEditor)
        editor.person = "María"
        editor.amountText = "150"
        #expect(await editor.save())
        await viewModel.sheetFinished()
        let first = try #require(viewModel.overview?.debts.first)
        #expect(first.person == "María")
        #expect(viewModel.debtLine(first) == "You owe")
    }

    @Test
    func repayingMoreThanWhatIsLeftIsPointedOut() async throws {
        let viewModel = await loaded()
        viewModel.openDebt(SampleData.IDs.juanDebt)
        let detail = try #require(viewModel.debtDetail)
        #expect(detail.title == "Juan owes you")
        detail.repaymentText = "301"
        #expect(detail.repaymentError == "That's more than what's left.")
        #expect(!detail.canRepay)
        detail.repaymentText = "300"
        await detail.repay()
        #expect(detail.debt.isSettled)
    }

    @Test
    func splittingStartsEqualAndStaysEqualUntilEdited() async throws {
        let store = InMemoryStore(sample: .standard)
        let expense = Transaction(
            date: now, description: "Dinner", kind: .expense, categoryID: "restaurants", amount: 900, currency: "NIO",
            accountID: SampleData.IDs.cash, exchangeRate: .single("NIO"),
        )
        try await store.save(expense)
        let split = SplitBillViewModel(transaction: expense, split: DefaultSplitTransactionUseCase(transactions: store, debts: store))
        #expect(split.shares.map(\.amountText) == ["450.00"])
        split.addPerson()
        #expect(split.shares.map(\.amountText) == ["300.00", "300.00"])
        #expect(split.yourShare == "Your share: C$300.00")
        let first = try #require(split.shares.first?.id)
        split.setAmount("500", for: first)
        split.addPerson()
        #expect(split.shares.map(\.amountText) == ["500", "300.00", ""])
        split.splitEqually()
        #expect(split.shares.map(\.amountText) == ["225.00", "225.00", "225.00"])
        #expect(!split.canSave)
        for (index, share) in split.shares.enumerated() {
            split.setPerson(["Juan", "Ana", "Luis"][index], for: share.id)
        }
        #expect(await split.save())
        #expect(await store.fetchPersonalDebts().count { $0.transactionID == expense.id } == 3)
    }

    @Test
    func aSecondSplitStartsFromWhatIsLeft() async throws {
        let store = InMemoryStore(sample: .standard)
        let expense = Transaction(
            date: now, description: "Dinner", kind: .expense, categoryID: "restaurants", amount: 900, currency: "NIO",
            accountID: SampleData.IDs.cash, exchangeRate: .single("NIO"),
        )
        try await store.save(expense)
        let useCase = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        try await useCase.execute(transactionID: expense.id, shares: [SplitShare(person: "Ana", amount: 300)])
        let split = SplitBillViewModel(transaction: expense, split: useCase)
        #expect(split.alreadySplit == nil)
        await split.load()
        #expect(split.alreadySplit == "Already split: C$600.00 left to share")
        #expect(split.shares.map(\.amountText) == ["300.00"])
    }

    @Test
    func theRepaymentFormOffersTheBankAndCashAccountsOnlyForWhatTheyOweMe() async throws {
        let store = InMemoryStore(sample: .standard)
        let useCases = DebtsPreview.useCases(store: store, now: now)
        let juan = try #require(await store.fetchPersonalDebts().first { $0.id == SampleData.IDs.juanDebt })
        let detail = DebtDetailViewModel(debt: juan, useCases: useCases, calendar: calendar, now: { [now] in now })
        await detail.load()
        #expect(detail.canDeposit)
        #expect(detail.depositOptions.first?.title == "Don't deposit")
        #expect(detail.depositAccountID == nil)
        detail.depositAccountID = SampleData.IDs.cash
        #expect(detail.depositNote?.hasPrefix("Records an income in") == true)
        detail.repaymentText = "50"
        await detail.repay()
        let repayment = try #require(detail.debt.repayments.last)
        #expect(repayment.transactionID != nil)
        #expect(detail.repaymentTitle(repayment).hasSuffix(" · deposited"))
        await detail.deleteRepayment(repayment)
        #expect(!detail.debt.repayments.contains { $0.id == repayment.id })

        let ana = try #require(await store.fetchPersonalDebts().first { $0.id == SampleData.IDs.anaDebt })
        let owed = DebtDetailViewModel(debt: ana, useCases: useCases, calendar: calendar, now: { [now] in now })
        await owed.load()
        #expect(!owed.canDeposit)
    }
}
