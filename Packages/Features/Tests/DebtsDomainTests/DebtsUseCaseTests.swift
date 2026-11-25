import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import DebtsDomain

@Suite("Debts use cases")
struct DebtsUseCaseTests {
    private let sample = SampleData.standard
    private let now = SampleData.defaultReferenceDate

    private func payUseCase(_ store: InMemoryStore) -> DefaultPayLoanInstallmentUseCase {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        )
        return DefaultPayLoanInstallmentUseCase(
            loans: store,
            recorder: MovementRecorder(prepare: DefaultPrepareTransactionUseCase(context: context)),
        )
    }

    @Test
    func theOverviewTotalsEachCurrencyApart() async throws {
        let store = InMemoryStore(sample: sample)
        let overview = try await DefaultGetDebtsUseCase(loans: store, debts: store, settings: store, now: { [now] in now }).execute()
        // Ten installments of C$5,500 left, Ana's US$40, and Juan's C$300 still owed.
        #expect(overview.totals.youOwe == [Money(55000, "NIO"), Money(40, "USD")])
        #expect(overview.totals.owedToYou == [Money(300, "NIO")])
        #expect(overview.debts.last?.id == SampleData.IDs.settledDebt)
        #expect(overview.loans.first?.next?.number == 3)
    }

    @Test
    func payingRecordsAConfirmedExpenseAndMarksTheInstallment() async throws {
        let store = InMemoryStore(sample: sample)
        let loan = try await payUseCase(store).execute(InstallmentPayment(
            loanID: SampleData.IDs.motorbikeLoan,
            source: .card(SampleData.IDs.savingsTransfer),
            categoryID: "other-expense",
            date: now,
        ))
        #expect(loan.paidCount == 3)
        let payment = try #require(loan.payments.last)
        #expect(payment.number == 3)
        let movement = try #require(await store.fetchTransactions(in: nil).first { $0.id == payment.transactionID })
        #expect(movement.description == "Motorbike · 3/12")
        #expect(movement.kind == .expense)
        #expect(movement.isConfirmed)
        #expect(movement.amount == 5500)
        #expect(movement.currency == "NIO")
        #expect(movement.accountID == SampleData.IDs.savings)
        #expect(await store.fetchLoans().first?.paidCount == 3)
    }

    @Test
    func markingAnInstallmentUnpaidDeletesItsExpenseAndMakesItDueAgain() async throws {
        let store = InMemoryStore(sample: sample)
        let pay = payUseCase(store)
        let paid = try await pay.execute(InstallmentPayment(
            loanID: SampleData.IDs.motorbikeLoan, source: .card(SampleData.IDs.savingsTransfer), categoryID: "other-expense", date: now,
        ))
        let movementID = try #require(paid.payments.last?.transactionID)
        let unpaid = try await pay.markUnpaid(loanID: paid.id, number: 3)
        #expect(unpaid.paidCount == 2)
        #expect(unpaid.nextNumber == 3)
        #expect(await store.fetchLoans().first { $0.id == paid.id }?.paidCount == 2)
        #expect(try await !store.fetchTransactions(in: nil).contains { $0.id == movementID })
        await #expect(throws: DomainError.invalidAmount) { try await pay.markUnpaid(loanID: paid.id, number: 3) }
    }

    @Test
    func aPaidOffLoanCantBePaidAgainAndNoMovementIsRecorded() async throws {
        let paid = Loan(
            name: "Done", borrowed: Money(10, "USD"), installmentAmount: 10, installmentCount: 1, firstDueDate: now,
            payments: [LoanPayment(number: 1, paidAt: now)],
        )
        let store = InMemoryStore(sample: sample)
        await store.save(paid)
        let before = try await store.fetchTransactions(in: nil).count
        await #expect(throws: DomainError.invalidAmount) {
            try await payUseCase(store).execute(InstallmentPayment(
                loanID: paid.id, source: .card(SampleData.IDs.savingsTransfer), categoryID: "other-expense", date: now,
            ))
        }
        #expect(try await store.fetchTransactions(in: nil).count == before)
    }

    @Test
    func savingALoanChecksItsNameCurrencyAndPaidInstallments() async throws {
        let store = InMemoryStore(sample: sample)
        let save = DefaultSaveLoanUseCase(loans: store, settings: store)
        let draft = LoanDraft(
            name: "  Car  ", lender: " ", borrowed: Money(9000, "USD"), installmentAmount: 400, installmentCount: 24, firstDueDate: now,
        )
        let created = try await save.execute(draft)
        #expect(created.name == "Car")
        #expect(created.lender == nil)
        await #expect(throws: DomainError.invalidCurrency("EUR")) {
            try await save.execute(LoanDraft(
                name: "X",
                borrowed: Money(1, "EUR"),
                installmentAmount: 1,
                installmentCount: 1,
                firstDueDate: now,
            ))
        }
        await #expect(throws: DomainError.missingName) {
            try await save.execute(LoanDraft(
                name: " ",
                borrowed: Money(1, "USD"),
                installmentAmount: 1,
                installmentCount: 1,
                firstDueDate: now,
            ))
        }
        // The motorbike has two installments paid, so it can't have just one.
        var edit = LoanDraft(
            id: SampleData.IDs.motorbikeLoan, name: "Motorbike", borrowed: Money(60000, "USD"), installmentAmount: 5500,
            installmentCount: 1, firstDueDate: now,
        )
        await #expect(throws: DomainError.invalidAmount) { try await save.execute(edit) }
        edit.installmentCount = 10
        let edited = try await save.execute(edit)
        #expect(edited.borrowed.currency == "NIO")
        #expect(edited.paidCount == 2)
    }

    @Test
    func debtsKeepTheirRepaymentsWhenEditedAndSettleWhenRepaid() async throws {
        let store = InMemoryStore(sample: sample)
        let save = DefaultSavePersonalDebtUseCase(debts: store, settings: store)
        let update = DefaultUpdatePersonalDebtUseCase(debts: store)
        // Juan already paid C$200 back, so the debt can't drop below that.
        await #expect(throws: DomainError.invalidAmount) {
            try await save.execute(PersonalDebtDraft(
                id: SampleData.IDs.juanDebt, person: "Juan", direction: .theyOweMe, amount: Money(100, "NIO"), date: now,
            ))
        }
        let edited = try await save.execute(PersonalDebtDraft(
            id: SampleData.IDs.juanDebt, person: "Juan Pérez", direction: .theyOweMe, amount: Money(600, "USD"), date: now, note: " ",
        ))
        #expect(edited.amount == Money(600, "NIO"))
        #expect(edited.note == nil)
        #expect(edited.repaid == 200)
        let settled = try await update.repay(id: edited.id, amount: 400, on: now)
        #expect(settled.isSettled)
        await #expect(throws: DomainError.invalidAmount) { try await update.repay(id: edited.id, amount: 1, on: now) }
        let ana = try await update.settle(id: SampleData.IDs.anaDebt, on: now)
        #expect(ana.isSettled && ana.remaining == 40)
        #expect(try await !update.reopen(id: ana.id).isSettled)
    }

    @Test
    func splittingAnExpenseCreatesOneDebtPerPersonLinkedToIt() async throws {
        let store = InMemoryStore(sample: sample)
        let expense = try #require(sample.transactions.first { $0.kind == .expense && $0.amount >= 10 })
        let split = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        let share = BillSplit.equalShare(of: expense.amount, people: 2)
        let created = try await split.execute(
            transactionID: expense.id,
            shares: [SplitShare(person: " Juan ", amount: share), SplitShare(person: "Ana", amount: share)],
        )
        #expect(created.map(\.person) == ["Juan", "Ana"])
        #expect(created.allSatisfy { $0.direction == .theyOweMe && $0.transactionID == expense.id })
        #expect(created.allSatisfy { $0.amount == Money(share, expense.currency) && $0.note == expense.description })
        #expect(await store.fetchPersonalDebts().count == sample.personalDebts.count + 2)

        await #expect(throws: DomainError.invalidAmount) {
            try await split.execute(transactionID: expense.id, shares: [SplitShare(person: "Too much", amount: expense.amount + 1)])
        }
        await #expect(throws: DomainError.missingName) {
            try await split.execute(transactionID: expense.id, shares: [SplitShare(person: " ", amount: 1)])
        }
        let income = try #require(sample.transactions.first { $0.kind == .income })
        await #expect(throws: DomainError.unsupportedTransactionKind(.income)) {
            try await split.execute(transactionID: income.id, shares: [SplitShare(person: "X", amount: 1)])
        }
    }

    @Test
    func editingASplitRenamesChangesAddsAndRemovesSharesInOneSave() async throws {
        let store = InMemoryStore(sample: sample)
        let expense = try #require(sample.transactions.first { $0.kind == .expense && $0.amount >= 10 })
        let split = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        let created = try await split.execute(
            transactionID: expense.id,
            shares: [SplitShare(person: "Ana", amount: 2), SplitShare(person: "Luis", amount: 1)],
        )
        let ana = try #require(created.first)
        let saved = try await split.save(
            transactionID: expense.id,
            shares: [SplitShare(debtID: ana.id, person: "Ana María", amount: 3), SplitShare(person: "Eva", amount: 1)],
        )
        #expect(saved.map(\.person) == ["Ana María", "Eva"])
        #expect(saved.first?.id == ana.id && saved.first?.amount == Money(3, expense.currency))
        let shares = try await split.shares(of: expense)
        #expect(Set(shares.map(\.person)) == ["Ana María", "Eva"])
        #expect(try await split.remaining(of: expense) == expense.amount - 4)

        await #expect(throws: DomainError.invalidAmount) {
            try await split.save(transactionID: expense.id, shares: [SplitShare(debtID: ana.id, person: "Ana", amount: expense.amount + 1)])
        }
        await #expect(throws: DomainError.notFound(SampleData.IDs.cash)) {
            try await split.save(transactionID: expense.id, shares: [SplitShare(debtID: SampleData.IDs.cash, person: "Ana", amount: 1)])
        }
        // Nothing was written by the refused saves.
        #expect(try await split.shares(of: expense).count == 2)
    }

    @Test
    func anEditedShareKeepsItsRepaymentsAndCantDropBelowThem() async throws {
        let store = InMemoryStore(sample: sample)
        let expense = try #require(sample.transactions.first { $0.kind == .expense && $0.amount >= 10 })
        let split = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        let ana = try #require(try await split.execute(transactionID: expense.id, shares: [SplitShare(person: "Ana", amount: 5)]).first)
        try await DefaultUpdatePersonalDebtUseCase(debts: store).repay(id: ana.id, amount: 4, on: now)
        await #expect(throws: DomainError.invalidAmount) {
            try await split.save(transactionID: expense.id, shares: [SplitShare(debtID: ana.id, person: "Ana", amount: 3)])
        }
        let kept = try #require(try await split.save(
            transactionID: expense.id,
            shares: [SplitShare(debtID: ana.id, person: "Ana", amount: 6)],
        ).first)
        #expect(kept.repaid == 4)
    }

    @Test
    func aSplitGetsOneLinkThatStopsWithTheSplit() async throws {
        let store = InMemoryStore(sample: sample)
        let expense = try #require(sample.transactions.first { $0.kind == .expense && $0.amount >= 10 })
        let split = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        await #expect(throws: DomainError.invalidAmount) { try await split.share(transactionID: expense.id) }
        try await split.execute(transactionID: expense.id, shares: [SplitShare(person: "Ana", amount: 1)])
        let shared = try await split.share(transactionID: expense.id)
        let token = try #require(shared.shareToken)
        #expect(token.count == 22 && token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(try await split.share(transactionID: expense.id).shareToken == token)
        #expect(try await split.stopSharing(transactionID: expense.id).shareToken == nil)
        #expect(try await split.share(transactionID: expense.id).shareToken != token)
        // Removing every share removes the split, and with it the link.
        try await split.save(transactionID: expense.id, shares: [])
        let stored = try #require(await store.fetchTransactions(in: nil).first { $0.id == expense.id })
        #expect(stored.shareToken == nil)
        #expect(try await split.shares(of: expense).isEmpty)
    }
}

/// What the app plugs in: the installment built through the movement-saving rules.
private struct MovementRecorder: InstallmentExpenseRecorder {
    let prepare: any PrepareTransactionUseCase

    func prepare(_ expense: InstallmentExpense) async throws(DomainError) -> Transaction {
        let source: PaymentSource = switch expense.source {
        case let .card(id): .card(id)
        case let .account(id): .account(id)
        }
        return try await prepare.execute(TransactionDraft(
            kind: .expense, amount: expense.amount.amount, currency: expense.amount.currency, categoryID: expense.categoryID,
            source: source, description: expense.description, date: expense.date,
        ))
    }
}
