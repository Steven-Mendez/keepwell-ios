import Core
import CreateTransactionDomain
import DebtsDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Creates or edits a loan: name, lender, what was borrowed, the installment, how many and how
/// often, and the first due day.
@MainActor
@Observable
public final class LoanEditorViewModel: Identifiable {
    public let id = UUID()
    public let editing: Loan?
    public var name = "" {
        didSet { errorMessage = nil }
    }

    public var lender = ""
    public var borrowedText = "" {
        didSet { errorMessage = nil }
    }

    public var installmentText = "" {
        didSet { errorMessage = nil }
    }

    public var countText = "" {
        didSet { errorMessage = nil }
    }

    public var frequency = LoanFrequency.monthly
    public var firstDueDate: Date
    /// Fixed when editing: the installments already paid were in it.
    public var currency: String
    public let currencyOptions: [String]
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    private let useCases: DebtsUseCases

    init(currencies: CurrencySettings, today: Date, useCases: DebtsUseCases) {
        editing = nil
        currency = currencies.principal
        currencyOptions = [currencies.principal] + (currencies.second.map { [$0] } ?? [])
        firstDueDate = today
        self.useCases = useCases
    }

    init(editing loan: Loan, useCases: DebtsUseCases) {
        editing = loan
        name = loan.name
        lender = loan.lender ?? ""
        let formatter = CurrencyFormatter()
        borrowedText = formatter.number(loan.borrowed.amount)
        installmentText = formatter.number(loan.installmentAmount)
        countText = "\(loan.installmentCount)"
        frequency = loan.frequency
        firstDueDate = loan.firstDueDate
        currency = loan.borrowed.currency
        currencyOptions = [loan.borrowed.currency]
        self.useCases = useCases
    }

    public var isCreating: Bool {
        editing == nil
    }

    public var title: String {
        isCreating ? String(localized: "New loan", bundle: #bundle) : String(localized: "Edit loan", bundle: #bundle)
    }

    public var frequencyOptions: [(value: LoanFrequency, title: String)] {
        [
            (.monthly, String(localized: "Monthly", bundle: #bundle)),
            (.weekly, String(localized: "Weekly", bundle: #bundle)),
        ]
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !borrowedText.isEmpty && !installmentText.isEmpty
            && !countText.isEmpty && !isSaving
    }

    /// "12 × C$5,500.00 = C$66,000.00": what the person will have paid, interest included.
    public var totalLine: String? {
        guard let installment = AmountInput.decimal(from: installmentText), let count = Int(countText), count > 0 else { return nil }
        let formatter = CurrencyFormatter()
        let total = formatter.string(from: installment * Decimal(count), currencyCode: currency)
        return String(localized: "You'll pay \(total) in total", bundle: #bundle)
    }

    public func save() async -> Bool {
        guard canSave else { return false }
        guard let borrowed = AmountInput.decimal(from: borrowedText), borrowed > 0,
              let installment = AmountInput.decimal(from: installmentText), installment > 0
        else {
            errorMessage = String(localized: "Amounts have to be greater than zero.", bundle: #bundle)
            return false
        }
        guard let count = Int(countText.trimmingCharacters(in: .whitespaces)), Loan.installmentCountRange.contains(count) else {
            errorMessage = String(localized: "Enter between 1 and 600 installments.", bundle: #bundle)
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await useCases.saveLoan.execute(LoanDraft(
                id: editing?.id,
                name: name,
                lender: lender,
                borrowed: Money(borrowed, currency),
                installmentAmount: installment,
                installmentCount: count,
                frequency: frequency,
                firstDueDate: firstDueDate,
            ))
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    public func delete() async -> Bool {
        guard let editing else { return false }
        do {
            try await useCases.delete.deleteLoan(id: editing.id)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    static func message(for error: DomainError) -> String {
        switch error {
        case .missingName: String(localized: "Give the loan a name.", bundle: #bundle)
        case .invalidAmount: String(localized: "There are more installments paid than that.", bundle: #bundle)
        default: String(localized: "We couldn't save the loan. Try again.", bundle: #bundle)
        }
    }
}

/// A loan's schedule and "Pay installment", which records the installment as an expense from the
/// account or card the person picks.
@MainActor
@Observable
public final class LoanDetailViewModel: Identifiable {
    public struct Method: Hashable, Sendable {
        public let source: InstallmentSource
        public let title: String
    }

    public let id = UUID()
    public private(set) var progress: LoanProgress
    public private(set) var context: TransactionContext?
    public var method: InstallmentSource?
    /// "Loan payments" until the person picks, or "Other" once they deleted it (`load()`).
    public var categoryID = TransactionCategory.otherExpenseID
    public var paymentDate: Date
    public private(set) var isPaying = false
    public private(set) var errorMessage: String?
    /// Something changed, so the list reloads when the sheet closes.
    public private(set) var didChange = false

    private let useCases: DebtsUseCases
    let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    init(progress: LoanProgress, useCases: DebtsUseCases, calendar: Calendar, now: @escaping () -> Date) {
        self.progress = progress
        self.useCases = useCases
        self.calendar = calendar
        self.now = now
        paymentDate = now()
    }

    public var loan: Loan {
        progress.loan
    }

    public func load() async {
        guard context == nil else { return }
        context = try? await useCases.paymentContext.execute()
        if categories.contains(where: { $0.id == TransactionCategory.loanPaymentsID }) {
            categoryID = TransactionCategory.loanPaymentsID
        }
        if let lastUsed = context?.lastUsedSource.map(InstallmentSource.init), methods.contains(where: { $0.source == lastUsed }) {
            method = lastUsed
        } else {
            method = methods.first?.source
        }
    }

    /// Every way to pay: each card or transfer channel, and accounts without any (cash).
    public var methods: [Method] {
        guard let context else { return [] }
        return context.accounts.open.flatMap { account -> [Method] in
            let cards = context.cards.filter { $0.accountID == account.id }
            guard !cards.isEmpty else { return [Method(source: .account(account.id), title: CardDisplay.name(of: account))] }
            return cards.map { Method(source: .card($0.id), title: CardDisplay.methodTitle($0, account: account)) }
        }
    }

    public var methodTitle: String {
        methods.first { $0.source == method }?.title ?? String(localized: "Choose", bundle: #bundle)
    }

    public var categories: [TransactionCategory] {
        TransactionCategory.ordered(context?.categories ?? []).filter { $0.kind == .expense }
    }

    public var categoryTitle: String {
        categories.first { $0.id == categoryID }.map(CategoryDisplay.name(of:)) ?? String(localized: "Choose", bundle: #bundle)
    }

    public var canPay: Bool {
        progress.next != nil && method != nil && !isPaying
    }

    /// "Pay 3/12 · C$5,500.00".
    public var payTitle: String {
        guard let next = progress.next else { return String(localized: "Paid off", bundle: #bundle) }
        let amount = formatter.string(loan.installment)
        return String(localized: "Pay \(next.number)/\(loan.installmentCount) · \(amount)", bundle: #bundle)
    }

    /// "4 of 12 paid · C$44,000.00 left".
    public func summary(hidden: Bool) -> String {
        let left = hidden ? DebtsViewModel.maskedAmount : formatter.string(progress.remainingMoney)
        return String(localized: "\(loan.paidCount) of \(loan.installmentCount) paid · \(left) left", bundle: #bundle)
    }

    public func borrowedLine(hidden: Bool) -> String {
        let borrowed = hidden ? DebtsViewModel.maskedAmount : formatter.string(loan.borrowed)
        guard let lender = loan.lender else { return String(localized: "Borrowed \(borrowed)", bundle: #bundle) }
        return String(localized: "Borrowed \(borrowed) from \(lender)", bundle: #bundle)
    }

    public func dueDay(_ installment: LoanInstallment) -> String {
        DebtDates.day(installment.dueDate, calendar: calendar)
    }

    public func pay() async {
        guard canPay, let method else { return }
        isPaying = true
        defer { isPaying = false }
        do {
            let paid = try await useCases.payInstallment.execute(InstallmentPayment(
                loanID: loan.id, source: method, categoryID: categoryID, date: paymentDate,
            ))
            progress = LoanProgress(loan: paid, today: now(), calendar: calendar)
            errorMessage = nil
            didChange = true
        } catch {
            errorMessage = String(localized: "We couldn't record the payment. Try again.", bundle: #bundle)
        }
    }

    /// "Mark unpaid": the installment is due again and the expense it recorded is deleted, so
    /// paying it again doesn't count it twice.
    public func markUnpaid(_ number: Int) async {
        do {
            let unpaid = try await useCases.payInstallment.markUnpaid(loanID: loan.id, number: number)
            progress = LoanProgress(loan: unpaid, today: now(), calendar: calendar)
            errorMessage = nil
            didChange = true
        } catch {
            errorMessage = String(localized: "We couldn't mark it unpaid. Try again.", bundle: #bundle)
        }
    }

    /// "Mark 3/12 unpaid?".
    public func unpayTitle(_ number: Int) -> String {
        String(localized: "Mark \(number)/\(loan.installmentCount) unpaid?", bundle: #bundle)
    }
}
