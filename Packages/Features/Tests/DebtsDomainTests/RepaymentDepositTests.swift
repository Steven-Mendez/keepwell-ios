import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import DebtsDomain

/// Repayments deposited into an account, deleting them, and splitting an expense twice. Same cases
/// as keepwell-web's `tests/domain/shared-expenses.test.ts`.
@Suite("Repayments deposited into an account")
struct RepaymentDepositTests {
    private let sample = SampleData.standard
    private let now = SampleData.defaultReferenceDate

    private func update(_ store: InMemoryStore, debts: (any PersonalDebtRepository)? = nil) -> DefaultUpdatePersonalDebtUseCase {
        let context = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store,
        )
        return DefaultUpdatePersonalDebtUseCase(
            debts: debts ?? store, categories: store, settings: store,
            recorder: IncomeRecorder(prepare: DefaultPrepareTransactionUseCase(context: context)),
        )
    }

    private func lunch(_ store: InMemoryStore) async throws -> Transaction {
        try #require(await store.fetchTransactions(in: nil).first { $0.description == "Lunch" })
    }

    /// "Lunch" split with Ana for 100 of its currency.
    private func splitLunch() async throws -> (store: InMemoryStore, lunch: Transaction, debt: PersonalDebt) {
        let store = InMemoryStore(sample: sample)
        let lunch = try await lunch(store)
        let created = try await DefaultSplitTransactionUseCase(transactions: store, debts: store)
            .execute(transactionID: lunch.id, shares: [SplitShare(person: "Ana", amount: 100)])
        return try (store, lunch, #require(created.first))
    }

    private func links(_ store: InMemoryStore) async throws -> DebtLinks {
        try await DebtLinks(store.fetchPersonalDebts(), deposits: store.fetchRepaymentDepositIDs())
    }

    @Test
    func recordsAnIncomeInTheAccountLinkedFiledUnderRefundsAndKeepsItOutOfIncome() async throws {
        let (store, lunch, debt) = try await splitLunch()
        let before = await store.fetchTransactions(in: nil).count
        let updated = try await update(store).repay(
            id: debt.id,
            amount: 100,
            on: now,
            deposit: RepaymentDeposit(accountID: SampleData.IDs.cash),
        )
        let repayment = try #require(updated.repayments.first)
        #expect(updated.settledAt == now)
        let movements = await store.fetchTransactions(in: nil)
        #expect(movements.count == before + 1)
        let movement = try #require(movements.first { $0.id == repayment.transactionID })
        #expect(movement.kind == .income)
        #expect(movement.isConfirmed)
        #expect(movement.amount == 100)
        #expect(movement.currency == lunch.currency)
        #expect(movement.accountID == SampleData.IDs.cash)
        #expect(movement.categoryID == "refunds")
        #expect(movement.description == "Ana · \(lunch.description)")
        let links = try await links(store)
        #expect(movement.isReimbursement(links))
        let month = YearMonth(containing: movement.date, calendar: .current)
        let summary = MonthlySummary(month: month, transactions: movements, currency: "USD", calendar: .current, debts: links)
        let gross = MonthlySummary(month: month, transactions: movements, currency: "USD", calendar: .current)
        #expect(gross.income - summary.income == movement.storedAmount(in: "USD"))
    }

    @Test
    func withoutADepositOnlyRecordsTheRepaymentAsBefore() async throws {
        let (store, _, debt) = try await splitLunch()
        let before = await store.fetchTransactions(in: nil).count
        let updated = try await update(store).repay(id: debt.id, amount: 40, on: now)
        #expect(updated.repayments.first?.transactionID == nil)
        #expect(await store.fetchTransactions(in: nil).count == before)
    }

    @Test
    func recordsNeitherTheMovementNorTheRepaymentWhenSavingFails() async throws {
        let (store, _, debt) = try await splitLunch()
        let before = await store.fetchTransactions(in: nil).count
        await #expect(throws: DomainError.persistence("disk full")) {
            try await update(store, debts: FailingDebts(store: store))
                .repay(id: debt.id, amount: 40, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.cash))
        }
        #expect(await store.fetchTransactions(in: nil).count == before)
        #expect(await store.fetchPersonalDebts().first { $0.id == debt.id }?.repayments.isEmpty == true)
    }

    @Test
    func depositsOnlyWhatSomeoneOwesThePerson() async throws {
        let store = InMemoryStore(sample: sample)
        let leo = PersonalDebt(person: "Leo", direction: .iOwe, amount: Money(50, "USD"), date: now)
        await store.save(leo)
        let before = await store.fetchTransactions(in: nil).count
        await #expect(throws: DomainError.unsupportedTransactionKind(.income)) {
            try await update(store).repay(id: leo.id, amount: 10, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.savings))
        }
        #expect(await store.fetchTransactions(in: nil).count == before)
        #expect(await store.fetchPersonalDebts().first { $0.id == leo.id }?.repayments.isEmpty == true)
    }

    @Test
    func depositsOnlyADebtInTheLedgersCurrencies() async throws {
        let store = InMemoryStore(sample: sample)
        let currencies = try #require(await store.load()?.currencies)
        let euros = PersonalDebt(person: "Eva", direction: .theyOweMe, amount: Money(50, "EUR"), date: now)
        await store.save(euros)
        #expect(!euros.canDepositRepayment(currencies: currencies))
        let inSecond = PersonalDebt(person: "Eva", direction: .theyOweMe, amount: Money(50, "NIO"), date: now)
        #expect(inSecond.canDepositRepayment(currencies: currencies))
        let owed = PersonalDebt(person: "Eva", direction: .iOwe, amount: Money(50, "USD"), date: now)
        #expect(!owed.canDepositRepayment(currencies: currencies))
        let before = await store.fetchTransactions(in: nil).count
        await #expect(throws: DomainError.invalidCurrency("EUR")) {
            try await update(store).repay(id: euros.id, amount: 10, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.cash))
        }
        #expect(await store.fetchTransactions(in: nil).count == before)
        // Without a deposit it records as before.
        #expect(try await update(store).repay(id: euros.id, amount: 10, on: now).repayments.count == 1)
    }

    @Test
    func deletingTheRepaymentDeletesItsMovementAndReopensADebtItSettled() async throws {
        let (store, _, debt) = try await splitLunch()
        let before = await store.fetchTransactions(in: nil).count
        let useCase = update(store)
        let repaid = try await useCase.repay(id: debt.id, amount: 100, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.cash))
        let repayment = try #require(repaid.repayments.first)
        let updated = try await useCase.deleteRepayment(debtID: debt.id, repaymentID: repayment.id)
        #expect(updated.repayments.isEmpty)
        #expect(updated.settledAt == nil)
        #expect(await store.fetchTransactions(in: nil).count == before)
    }

    @Test
    func deletingTheMovementLeavesTheRepaymentWhoseDeletionThenOnlyChangesTheDebt() async throws {
        let (store, _, debt) = try await splitLunch()
        let useCase = update(store)
        let repaid = try await useCase.repay(id: debt.id, amount: 40, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.cash))
        let repayment = try #require(repaid.repayments.first)
        try await store.deleteTransaction(id: #require(repayment.transactionID))
        #expect(await store.fetchPersonalDebts().first { $0.id == debt.id }?.repayments.count == 1)
        let updated = try await useCase.deleteRepayment(debtID: debt.id, repaymentID: repayment.id)
        #expect(updated.repayments.isEmpty)
    }

    @Test
    func keepsADebtSettledByHandSettledWhenARepaymentIsDeleted() async throws {
        let (store, _, debt) = try await splitLunch()
        let useCase = update(store)
        let repaid = try await useCase.repay(id: debt.id, amount: 40, on: now)
        let byHand = now.addingTimeInterval(86400 * 10)
        _ = try await useCase.settle(id: debt.id, on: byHand)
        let updated = try await useCase.deleteRepayment(debtID: debt.id, repaymentID: #require(repaid.repayments.first?.id))
        #expect(updated.settledAt == byHand)
    }

    @Test
    func deletingTheDebtKeepsItsDepositsAsMovementsThatStillArentIncome() async throws {
        let (store, _, debt) = try await splitLunch()
        let repaid = try await update(store)
            .repay(id: debt.id, amount: 40, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.cash))
        let movementID = try #require(repaid.repayments.first?.transactionID)
        try await DefaultDeleteDebtUseCase(loans: store, debts: store).deletePersonalDebt(id: debt.id)
        let movement = try #require(await store.fetchTransactions(in: nil).first { $0.id == movementID })
        #expect(await !store.fetchPersonalDebts().contains { $0.id == debt.id })
        #expect(await store.fetchRepaymentDepositIDs().contains(movementID))
        #expect(try await movement.isReimbursement(links(store)))
        // The alive debts alone no longer know it: totals over the ledger pass the deposits.
        #expect(await !movement.isReimbursement(DebtLinks(store.fetchPersonalDebts())))
    }

    @Test
    func aRepaymentDroppedByASaveKeepsItsLinkToo() async throws {
        let (store, _, debt) = try await splitLunch()
        let repaid = try await update(store)
            .repay(id: debt.id, amount: 40, on: now, deposit: RepaymentDeposit(accountID: SampleData.IDs.cash))
        let movementID = try #require(repaid.repayments.first?.transactionID)
        await store.save(repaid.with(repayments: [], settledAt: nil))
        #expect(await store.fetchRepaymentDepositIDs() == [movementID])
    }

    // MARK: Splitting twice

    @Test
    func sharesOnlyWhatEarlierSplitsLeftSoTheSharesNeverExceedTheExpense() async throws {
        let store = InMemoryStore(sample: sample)
        let lunch = try await lunch(store)
        let split = DefaultSplitTransactionUseCase(transactions: store, debts: store)
        #expect(lunch.splitRemaining(debts: []) == lunch.amount)
        let ana = try #require(try await split.execute(
            transactionID: lunch.id,
            shares: [SplitShare(person: "Ana", amount: lunch.amount - 100)],
        ).first)
        #expect(try await split.remaining(of: lunch) == 100)
        await #expect(throws: DomainError.invalidAmount) {
            try await split.execute(transactionID: lunch.id, shares: [SplitShare(person: "Luis", amount: 101)])
        }
        try await split.execute(transactionID: lunch.id, shares: [SplitShare(person: "Luis", amount: 100)])
        #expect(try await split.remaining(of: lunch) == 0)
        await #expect(throws: DomainError.invalidAmount) {
            try await split.execute(transactionID: lunch.id, shares: [SplitShare(person: "Eva", amount: Decimal(string: "0.01") ?? 1)])
        }
        // A deleted share frees its part.
        try await store.deletePersonalDebt(id: ana.id)
        #expect(try await split.remaining(of: lunch) == lunch.amount - 100)
    }

    @Test
    func onlyAnExpenseHasAnythingToSplit() throws {
        let income = try #require(sample.transactions.first { $0.kind == .income })
        #expect(income.splitRemaining(debts: []) == 0)
    }
}

/// What the app plugs in: the income built through the movement-saving rules.
private struct IncomeRecorder: RepaymentIncomeRecorder {
    let prepare: any PrepareTransactionUseCase

    func prepare(_ income: RepaymentIncome) async throws(DomainError) -> Transaction {
        try await prepare.execute(TransactionDraft(
            kind: .income, amount: income.amount.amount, currency: income.amount.currency, categoryID: income.categoryID,
            source: .account(income.accountID), description: income.description, date: income.date,
        ))
    }
}

/// The store, except that saving a debt with its deposit fails.
private struct FailingDebts: PersonalDebtRepository {
    let store: InMemoryStore

    func fetchPersonalDebts() async -> [PersonalDebt] {
        await store.fetchPersonalDebts()
    }

    func save(_ debt: PersonalDebt) async {
        await store.save(debt)
    }

    func deletePersonalDebt(id: UUID) async throws(DomainError) {
        try await store.deletePersonalDebt(id: id)
    }

    func save(_: PersonalDebt, recording _: Transaction) throws(DomainError) {
        throw .persistence("disk full")
    }

    func save(_ debt: PersonalDebt, deletingTransaction transactionID: UUID?) async {
        await store.save(debt, deletingTransaction: transactionID)
    }

    func fetchRepaymentDepositIDs() async -> [UUID] {
        await store.fetchRepaymentDepositIDs()
    }
}
