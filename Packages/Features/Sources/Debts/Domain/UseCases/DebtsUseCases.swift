import Domain
import Foundation

public protocol GetDebtsUseCase: Sendable {
    func execute() async throws(DomainError) -> DebtsOverview
}

public struct DefaultGetDebtsUseCase: GetDebtsUseCase {
    private let loans: any LoanRepository
    private let debts: any PersonalDebtRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        loans: any LoanRepository,
        debts: any PersonalDebtRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.loans = loans
        self.debts = debts
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    public func execute() async throws(DomainError) -> DebtsOverview {
        let currencies = try await settings.load()?.currencies ?? .initial
        return try await DebtsOverview(
            currencies: currencies,
            loans: loans.fetchLoans(),
            debts: debts.fetchPersonalDebts(),
            today: now(),
            calendar: calendar,
        )
    }
}

/// Names are trimmed and cut to the limit, like a goal's.
enum DebtNames {
    static func cleaned(_ text: String, limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Creates or edits a loan. A new one is in the principal or second currency with nothing paid;
/// an edit keeps its currency and the installments already paid, so the count can't drop below them.
public protocol SaveLoanUseCase: Sendable {
    @discardableResult
    func execute(_ draft: LoanDraft) async throws(DomainError) -> Loan
}

public struct DefaultSaveLoanUseCase: SaveLoanUseCase {
    private let loans: any LoanRepository
    private let settings: any SettingsRepository
    private let makeID: @Sendable () -> UUID

    public init(loans: any LoanRepository, settings: any SettingsRepository, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.loans = loans
        self.settings = settings
        self.makeID = makeID
    }

    public func execute(_ draft: LoanDraft) async throws(DomainError) -> Loan {
        let name = DebtNames.cleaned(draft.name, limit: Loan.maxNameLength)
        guard !name.isEmpty else { throw .missingName }
        let lender = DebtNames.cleaned(draft.lender, limit: Loan.maxNameLength)
        let existing: Loan?
        if let id = draft.id {
            guard let found = try await loans.fetchLoans().first(where: { $0.id == id }) else { throw .notFound(id) }
            existing = found
        } else {
            let currencies = try await settings.load()?.currencies ?? .initial
            try Transaction.checkCurrency(draft.borrowed.currency, currencies: currencies)
            existing = nil
        }
        let payments = existing?.payments ?? []
        guard draft.installmentCount >= payments.map(\.number).max() ?? 0 else { throw .invalidAmount }
        let loan = Loan(
            id: existing?.id ?? makeID(),
            name: name,
            lender: lender.isEmpty ? nil : lender,
            borrowed: Money(draft.borrowed.amount, existing?.borrowed.currency ?? draft.borrowed.currency),
            installmentAmount: draft.installmentAmount,
            installmentCount: draft.installmentCount,
            frequency: draft.frequency,
            firstDueDate: draft.firstDueDate,
            payments: payments,
        )
        try loan.check()
        try await loans.save(loan)
        return loan
    }
}

/// "Pay installment": records the installment as a confirmed expense from the chosen account or
/// card, checked like a movement the person types, and marks it paid in the same write, so an
/// installment is never paid without its expense nor an expense left without its installment.
/// "Mark unpaid" undoes it the same way: the installment is due again and its expense is deleted.
public protocol PayLoanInstallmentUseCase: Sendable {
    @discardableResult
    func execute(_ payment: InstallmentPayment) async throws(DomainError) -> Loan
    @discardableResult
    func markUnpaid(loanID: UUID, number: Int) async throws(DomainError) -> Loan
}

public struct DefaultPayLoanInstallmentUseCase: PayLoanInstallmentUseCase {
    private let loans: any LoanRepository
    private let recorder: any InstallmentExpenseRecorder

    public init(loans: any LoanRepository, recorder: any InstallmentExpenseRecorder) {
        self.loans = loans
        self.recorder = recorder
    }

    /// "Motorbike · 3/12": the loan and which installment, the same on both apps.
    public static func description(of loan: Loan, number: Int) -> String {
        "\(loan.name) · \(number)/\(loan.installmentCount)"
    }

    public func execute(_ payment: InstallmentPayment) async throws(DomainError) -> Loan {
        guard let loan = try await loans.fetchLoans().first(where: { $0.id == payment.loanID }) else {
            throw .notFound(payment.loanID)
        }
        guard let number = loan.nextNumber else { throw .invalidAmount }
        let expense = try await recorder.prepare(InstallmentExpense(
            amount: loan.installment,
            categoryID: payment.categoryID,
            source: payment.source,
            description: Self.description(of: loan, number: number),
            date: payment.date,
        ))
        let paid = try loan.paying(at: payment.date, transactionID: expense.id)
        try await loans.save(paid, recording: expense)
        return paid
    }

    public func markUnpaid(loanID: UUID, number: Int) async throws(DomainError) -> Loan {
        guard let loan = try await loans.fetchLoans().first(where: { $0.id == loanID }) else { throw .notFound(loanID) }
        let (unpaid, payment) = try loan.unpaying(number: number)
        try await loans.save(unpaid, deletingTransaction: payment.transactionID)
        return unpaid
    }
}

/// Creates or edits a personal debt. A new one is in the principal or second currency; an edit
/// keeps its currency, repayments and settling, and its amount can't drop below what was repaid.
public protocol SavePersonalDebtUseCase: Sendable {
    @discardableResult
    func execute(_ draft: PersonalDebtDraft) async throws(DomainError) -> PersonalDebt
}

public struct DefaultSavePersonalDebtUseCase: SavePersonalDebtUseCase {
    private let debts: any PersonalDebtRepository
    private let settings: any SettingsRepository
    private let calendar: Calendar
    private let makeID: @Sendable () -> UUID

    public init(
        debts: any PersonalDebtRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .current,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        self.debts = debts
        self.settings = settings
        self.calendar = calendar
        self.makeID = makeID
    }

    public func execute(_ draft: PersonalDebtDraft) async throws(DomainError) -> PersonalDebt {
        let person = DebtNames.cleaned(draft.person, limit: PersonalDebt.maxNameLength)
        guard !person.isEmpty else { throw .missingName }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = draft.dueDate.map { calendar.startOfDay(for: $0) }
        if let dueDate, dueDate < calendar.startOfDay(for: draft.date) {
            throw .invalidDueDate
        }
        let existing: PersonalDebt?
        if let id = draft.id {
            guard let found = try await debts.fetchPersonalDebts().first(where: { $0.id == id }) else { throw .notFound(id) }
            existing = found
        } else {
            let currencies = try await settings.load()?.currencies ?? .initial
            try Transaction.checkCurrency(draft.amount.currency, currencies: currencies)
            existing = nil
        }
        let debt = PersonalDebt(
            id: existing?.id ?? makeID(),
            person: person,
            direction: draft.direction,
            amount: Money(draft.amount.amount, existing?.amount.currency ?? draft.amount.currency),
            date: draft.date,
            note: note.isEmpty ? nil : note,
            repayments: existing?.repayments ?? [],
            settledAt: existing?.settledAt,
            transactionID: existing?.transactionID,
            dueDate: dueDate,
        )
        try debt.checkAmounts()
        try await debts.save(debt)
        return debt
    }
}

/// Repayments, settling and reopening. Only the debt changes, except a repayment deposited into an
/// account, which also records an income movement (that no total counts as income).
public protocol UpdatePersonalDebtUseCase: Sendable {
    /// "Record repayment". With `deposit` (only on a "they owe me" debt in the principal or second
    /// currency, `PersonalDebt.canDepositRepayment`: otherwise `.unsupportedTransactionKind(.income)`
    /// or `.invalidCurrency`, nothing written), it also records a confirmed income of the
    /// repayment's amount and currency into that account and links it, in one write: a failure
    /// records neither.
    @discardableResult
    func repay(id: UUID, amount: Decimal, on day: Date, deposit: RepaymentDeposit?) async throws(DomainError) -> PersonalDebt
    /// Deletes one repayment and the movement it deposited, in one write, as "Mark unpaid" does for
    /// a loan. A debt that repayment settled opens again; one settled by hand stays settled.
    @discardableResult
    func deleteRepayment(debtID: UUID, repaymentID: UUID) async throws(DomainError) -> PersonalDebt
    @discardableResult
    func settle(id: UUID, on day: Date) async throws(DomainError) -> PersonalDebt
    @discardableResult
    func reopen(id: UUID) async throws(DomainError) -> PersonalDebt
}

extension UpdatePersonalDebtUseCase {
    /// Records the repayment only.
    @discardableResult
    public func repay(id: UUID, amount: Decimal, on day: Date) async throws(DomainError) -> PersonalDebt {
        try await repay(id: id, amount: amount, on: day, deposit: nil)
    }
}

public struct DefaultUpdatePersonalDebtUseCase: UpdatePersonalDebtUseCase {
    private let debts: any PersonalDebtRepository
    private let categories: (any CategoryRepository)?
    private let settings: (any SettingsRepository)?
    private let recorder: (any RepaymentIncomeRecorder)?

    /// Without `recorder`, a deposit can't be recorded and throws `.unsupportedTransactionKind`;
    /// without `settings`, the ledger's currencies are unknown and it throws `.invalidCurrency`.
    public init(
        debts: any PersonalDebtRepository,
        categories: (any CategoryRepository)? = nil,
        settings: (any SettingsRepository)? = nil,
        recorder: (any RepaymentIncomeRecorder)? = nil,
    ) {
        self.debts = debts
        self.categories = categories
        self.settings = settings
        self.recorder = recorder
    }

    public func repay(id: UUID, amount: Decimal, on day: Date, deposit: RepaymentDeposit?) async throws(DomainError) -> PersonalDebt {
        let debt = try await find(id)
        guard let deposit else { return try await store(debt.repaying(amount, on: day)) }
        guard debt.direction == .theyOweMe, let recorder else { throw .unsupportedTransactionKind(.income) }
        guard let currencies = try await settings?.load()?.currencies, debt.canDepositRepayment(currencies: currencies) else {
            throw .invalidCurrency(debt.amount.currency)
        }
        // Checked before the movement is built, so a repayment too large records nothing.
        _ = try debt.repaying(amount, on: day)
        var categoryID = deposit.categoryID
        if categoryID == nil {
            categoryID = try await PersonalDebt.repaymentCategoryID(in: categories?.fetchCategories() ?? [])
        }
        let income = try await recorder.prepare(RepaymentIncome(
            amount: Money(amount, debt.amount.currency),
            categoryID: categoryID ?? TransactionCategory.otherIncomeID,
            accountID: deposit.accountID,
            description: debt.repaymentDescription,
            date: day,
        ))
        let repaid = try debt.repaying(amount, on: day, transactionID: income.id)
        try await debts.save(repaid, recording: income)
        return repaid
    }

    public func deleteRepayment(debtID: UUID, repaymentID: UUID) async throws(DomainError) -> PersonalDebt {
        let (debt, repayment) = try await find(debtID).removingRepayment(id: repaymentID)
        try await debts.save(debt, deletingTransaction: repayment.transactionID)
        return debt
    }

    public func settle(id: UUID, on day: Date) async throws(DomainError) -> PersonalDebt {
        try await store(find(id).settled(at: day))
    }

    public func reopen(id: UUID) async throws(DomainError) -> PersonalDebt {
        try await store(find(id).reopened())
    }

    private func find(_ id: UUID) async throws(DomainError) -> PersonalDebt {
        guard let debt = try await debts.fetchPersonalDebts().first(where: { $0.id == id }) else { throw .notFound(id) }
        return debt
    }

    private func store(_ debt: PersonalDebt) async throws(DomainError) -> PersonalDebt {
        try await debts.save(debt)
        return debt
    }
}

/// Deletes a loan or a personal debt, leaving a tombstone like every other record. A loan's paid
/// installments and a debt's deposited repayments stay as movements: they really happened.
public protocol DeleteDebtUseCase: Sendable {
    func deleteLoan(id: UUID) async throws(DomainError)
    func deletePersonalDebt(id: UUID) async throws(DomainError)
}

public struct DefaultDeleteDebtUseCase: DeleteDebtUseCase {
    private let loans: any LoanRepository
    private let debts: any PersonalDebtRepository

    public init(loans: any LoanRepository, debts: any PersonalDebtRepository) {
        self.loans = loans
        self.debts = debts
    }

    public func deleteLoan(id: UUID) async throws(DomainError) {
        try await loans.deleteLoan(id: id)
    }

    public func deletePersonalDebt(id: UUID) async throws(DomainError) {
        try await debts.deletePersonalDebt(id: id)
    }
}

/// "Split": one "they owe me" debt per person for their share of an expense the person paid,
/// each linked to the movement. The movement itself doesn't change. The shares together can't
/// exceed what earlier splits left of it (`Transaction.splitRemaining`).
public protocol SplitTransactionUseCase: Sendable {
    @discardableResult
    func execute(transactionID: UUID, shares: [SplitShare]) async throws(DomainError) -> [PersonalDebt]
    /// What is left of the expense to split, in its currency.
    func remaining(of transaction: Transaction) async throws(DomainError) -> Decimal
}

public struct DefaultSplitTransactionUseCase: SplitTransactionUseCase {
    private let transactions: any TransactionRepository
    private let debts: any PersonalDebtRepository
    private let makeID: @Sendable () -> UUID

    public init(
        transactions: any TransactionRepository,
        debts: any PersonalDebtRepository,
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        self.transactions = transactions
        self.debts = debts
        self.makeID = makeID
    }

    public func execute(transactionID: UUID, shares: [SplitShare]) async throws(DomainError) -> [PersonalDebt] {
        guard let expense = try await transactions.fetchTransactions(in: nil).first(where: { $0.id == transactionID }) else {
            throw .notFound(transactionID)
        }
        guard expense.kind == .expense else { throw .unsupportedTransactionKind(expense.kind) }
        let people = shares.map { DebtNames.cleaned($0.person, limit: PersonalDebt.maxNameLength) }
        guard !people.contains(where: \.isEmpty) else { throw .missingName }
        // A second split shares only what the first left, so the shares never add up to more than
        // the expense.
        try await BillSplit.check(shares.map(\.amount), total: remaining(of: expense))
        let created = zip(people, shares).map { person, share in
            PersonalDebt(
                id: makeID(),
                person: person,
                direction: .theyOweMe,
                amount: Money(share.amount, expense.currency),
                date: expense.date,
                note: expense.description,
                transactionID: expense.id,
            )
        }
        for debt in created {
            try await debts.save(debt)
        }
        return created
    }

    public func remaining(of transaction: Transaction) async throws(DomainError) -> Decimal {
        try await transaction.splitRemaining(debts: debts.fetchPersonalDebts())
    }
}
