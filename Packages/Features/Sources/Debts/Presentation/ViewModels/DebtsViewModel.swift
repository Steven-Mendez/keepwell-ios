import Core
import CreateTransactionDomain
import DebtsDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// The use cases the debts screens share, so each view model gets the ones it needs from one value.
public struct DebtsUseCases: Sendable {
    public let getDebts: any GetDebtsUseCase
    public let saveLoan: any SaveLoanUseCase
    public let payInstallment: any PayLoanInstallmentUseCase
    public let paymentContext: any GetTransactionContextUseCase
    public let saveDebt: any SavePersonalDebtUseCase
    public let updateDebt: any UpdatePersonalDebtUseCase
    public let delete: any DeleteDebtUseCase

    public init(
        getDebts: any GetDebtsUseCase,
        saveLoan: any SaveLoanUseCase,
        payInstallment: any PayLoanInstallmentUseCase,
        paymentContext: any GetTransactionContextUseCase,
        saveDebt: any SavePersonalDebtUseCase,
        updateDebt: any UpdatePersonalDebtUseCase,
        delete: any DeleteDebtUseCase,
    ) {
        self.getDebts = getDebts
        self.saveLoan = saveLoan
        self.payInstallment = payInstallment
        self.paymentContext = paymentContext
        self.saveDebt = saveDebt
        self.updateDebt = updateDebt
        self.delete = delete
    }
}

/// Drives "Debts": the totals per currency, loans with their next installment and the people who
/// owe or are owed, plus the sheets each row opens.
@MainActor
@Observable
public final class DebtsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(DebtsOverview)
        case failed
    }

    public private(set) var state = State.loading
    public var loanEditor: LoanEditorViewModel?
    public var loanDetail: LoanDetailViewModel?
    public var debtEditor: DebtEditorViewModel?
    public var debtDetail: DebtDetailViewModel?

    let useCases: DebtsUseCases
    let calendar: Calendar
    let now: () -> Date
    let formatter = CurrencyFormatter()
    static let maskedAmount = "••••"

    public init(useCases: DebtsUseCases, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.useCases = useCases
        self.calendar = calendar
        self.now = now
    }

    public var overview: DebtsOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public var isEmpty: Bool {
        overview.map { $0.loans.isEmpty && $0.debts.isEmpty } ?? false
    }

    public func load() async {
        do {
            state = try await .loaded(useCases.getDebts.execute())
        } catch {
            state = .failed
        }
    }

    // MARK: Sheets

    public func newLoan() {
        guard let overview else { return }
        loanEditor = LoanEditorViewModel(currencies: overview.currencies, today: now(), useCases: useCases)
    }

    public func newDebt(_ direction: DebtDirection = .theyOweMe) {
        guard let overview else { return }
        debtEditor = DebtEditorViewModel(currencies: overview.currencies, direction: direction, today: now(), useCases: useCases)
    }

    public func openLoan(_ id: UUID) {
        guard let progress = overview?.loan(id) else { return }
        loanDetail = LoanDetailViewModel(progress: progress, useCases: useCases, calendar: calendar, now: now)
    }

    public func editLoan(_ loan: Loan) {
        loanDetail = nil
        loanEditor = LoanEditorViewModel(editing: loan, useCases: useCases)
    }

    public func openDebt(_ id: UUID) {
        guard let debt = overview?.debt(id) else { return }
        debtDetail = DebtDetailViewModel(debt: debt, useCases: useCases, calendar: calendar, now: now)
    }

    public func editDebt(_ debt: PersonalDebt) {
        debtDetail = nil
        debtEditor = DebtEditorViewModel(editing: debt, useCases: useCases)
    }

    /// After a sheet saved or deleted, so the list shows the stored result.
    public func sheetFinished() async {
        loanEditor = nil
        debtEditor = nil
        loanDetail = nil
        debtDetail = nil
        await load()
    }

    // MARK: Text

    /// "C$19,166.70 · US$40.00", one amount per currency, or "Nothing" without any.
    public func totals(_ lines: [Money], hidden: Bool) -> String {
        guard !lines.isEmpty else { return String(localized: "Nothing", bundle: #bundle) }
        return lines.map { hidden ? Self.maskedAmount : formatter.string($0) }.joined(separator: " · ")
    }

    /// "Next: 3/12 on Nov 28 · C$5,500.00", "Overdue: …" or "Paid off".
    public func loanLine(_ progress: LoanProgress, hidden: Bool) -> String {
        guard let next = progress.next else { return String(localized: "Paid off", bundle: #bundle) }
        let amount = hidden ? Self.maskedAmount : formatter.string(progress.loan.installment)
        let number = "\(next.number)/\(progress.loan.installmentCount)"
        let day = DebtDates.day(next.dueDate, calendar: calendar)
        return progress.isNextOverdue
            ? String(localized: "Overdue: \(number) on \(day) · \(amount)", bundle: #bundle)
            : String(localized: "Next: \(number) on \(day) · \(amount)", bundle: #bundle)
    }

    /// "C$19,166.70 left".
    public func loanLeft(_ progress: LoanProgress, hidden: Bool) -> String {
        let amount = hidden ? Self.maskedAmount : formatter.string(progress.remainingMoney)
        return String(localized: "\(amount) left", bundle: #bundle)
    }

    /// "Owes you" or "You owe", then the note.
    public func debtLine(_ debt: PersonalDebt) -> String {
        let direction = DebtDisplay.direction(debt.direction)
        guard let note = debt.note else { return direction }
        return "\(direction) · \(note)"
    }

    /// "Due Nov 28, 2026", "Due today" or "Overdue · 3 days" under the amount; `nil` when nothing is due.
    public func debtDue(_ debt: PersonalDebt) -> DebtDueLine? {
        DebtDisplay.due(debt, today: now(), calendar: calendar)
    }

    /// What is left, or "Settled".
    public func debtAmount(_ debt: PersonalDebt, hidden: Bool) -> String {
        if debt.isSettled {
            return String(localized: "Settled", bundle: #bundle)
        }
        return hidden ? Self.maskedAmount : formatter.string(debt.remainingMoney)
    }
}

/// Paid installments over all of them, for the bar.
func paidFraction(_ progress: LoanProgress) -> Double {
    let count = progress.loan.installmentCount
    return count > 0 ? min(Double(progress.loan.paidCount) / Double(count), 1) : 0
}

/// How dates and directions read on the debts screens.
public enum DebtDisplay {
    public static func direction(_ direction: DebtDirection) -> String {
        switch direction {
        case .theyOweMe: String(localized: "Owes you", bundle: #bundle)
        case .iOwe: String(localized: "You owe", bundle: #bundle)
        }
    }

    /// Where a debt's due date stands, said in words: color only adds to it.
    public static func due(_ debt: PersonalDebt, today: Date, calendar: Calendar) -> DebtDueLine? {
        guard let status = debt.dueStatus(today: today, calendar: calendar), let dueDate = debt.dueDate else { return nil }
        return switch status {
        case .upcoming:
            DebtDueLine(
                text: String(localized: "Due \(DebtDates.day(dueDate, calendar: calendar))", bundle: #bundle),
                isOverdue: false,
            )
        case .today:
            DebtDueLine(text: String(localized: "Due today", bundle: #bundle), isOverdue: false)
        case let .overdue(daysLate):
            DebtDueLine(text: String(localized: "Overdue · \(daysLate) days", bundle: #bundle), isOverdue: true)
        }
    }
}

/// The line under a debt's amount about its due date.
public struct DebtDueLine: Equatable, Sendable {
    public let text: String
    public let isOverdue: Bool
}

enum DebtDates {
    /// "Nov 28, 2026" in the person's locale.
    static func day(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
