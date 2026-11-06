import Core
import DebtsDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Creates or edits a personal debt: who, which way, how much, when and a note.
@MainActor
@Observable
public final class DebtEditorViewModel: Identifiable {
    public let id = UUID()
    public let editing: PersonalDebt?
    public var direction: DebtDirection
    public var person = "" {
        didSet { errorMessage = nil }
    }

    public var amountText = "" {
        didSet { errorMessage = nil }
    }

    public var date: Date
    public var note = ""
    /// Fixed when editing: repayments were counted in it.
    public var currency: String
    public let currencyOptions: [String]
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    private let useCases: DebtsUseCases

    init(currencies: CurrencySettings, direction: DebtDirection, today: Date, useCases: DebtsUseCases) {
        editing = nil
        self.direction = direction
        currency = currencies.principal
        currencyOptions = [currencies.principal] + (currencies.second.map { [$0] } ?? [])
        date = today
        self.useCases = useCases
    }

    init(editing debt: PersonalDebt, useCases: DebtsUseCases) {
        editing = debt
        direction = debt.direction
        person = debt.person
        amountText = CurrencyFormatter().number(debt.amount.amount)
        date = debt.date
        note = debt.note ?? ""
        currency = debt.amount.currency
        currencyOptions = [debt.amount.currency]
        self.useCases = useCases
    }

    public var isCreating: Bool {
        editing == nil
    }

    public var title: String {
        isCreating ? String(localized: "New debt", bundle: #bundle) : String(localized: "Edit debt", bundle: #bundle)
    }

    public var directionOptions: [(value: DebtDirection, title: String)] {
        [
            (.theyOweMe, String(localized: "They owe me", bundle: #bundle)),
            (.iOwe, String(localized: "I owe", bundle: #bundle)),
        ]
    }

    public var canSave: Bool {
        !person.trimmingCharacters(in: .whitespaces).isEmpty && !amountText.isEmpty && !isSaving
    }

    public func save() async -> Bool {
        guard canSave else { return false }
        guard let amount = AmountInput.decimal(from: amountText), amount > 0 else {
            errorMessage = String(localized: "Amounts have to be greater than zero.", bundle: #bundle)
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await useCases.saveDebt.execute(PersonalDebtDraft(
                id: editing?.id, person: person, direction: direction, amount: Money(amount, currency), date: date, note: note,
            ))
            return true
        } catch {
            errorMessage = switch error {
            case .missingName: String(localized: "Write who it's with.", bundle: #bundle)
            case .invalidAmount: String(localized: "It can't be less than what was already paid back.", bundle: #bundle)
            default: String(localized: "We couldn't save the debt. Try again.", bundle: #bundle)
            }
            return false
        }
    }

    public func delete() async -> Bool {
        guard let editing else { return false }
        do {
            try await useCases.delete.deletePersonalDebt(id: editing.id)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't save the debt. Try again.", bundle: #bundle)
            return false
        }
    }
}

/// One personal debt: what is left, its repayments, and "Record repayment", "Mark as settled"
/// or "Reopen". None of them records a movement.
@MainActor
@Observable
public final class DebtDetailViewModel: Identifiable {
    public let id = UUID()
    public private(set) var debt: PersonalDebt
    public var repaymentText = "" {
        didSet { errorMessage = nil }
    }

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    public private(set) var didChange = false
    private let useCases: DebtsUseCases
    let calendar: Calendar
    private let now: () -> Date
    let formatter = CurrencyFormatter()

    init(debt: PersonalDebt, useCases: DebtsUseCases, calendar: Calendar, now: @escaping () -> Date) {
        self.debt = debt
        self.useCases = useCases
        self.calendar = calendar
        self.now = now
    }

    /// "Juan owes you" or "You owe Juan".
    public var title: String {
        switch debt.direction {
        case .theyOweMe: String(localized: "\(debt.person) owes you", bundle: #bundle)
        case .iOwe: String(localized: "You owe \(debt.person)", bundle: #bundle)
        }
    }

    /// "C$300.00 left of C$500.00".
    public func summary(hidden: Bool) -> String {
        let left = hidden ? DebtsViewModel.maskedAmount : formatter.string(debt.remainingMoney)
        let total = hidden ? DebtsViewModel.maskedAmount : formatter.string(debt.amount)
        return String(localized: "\(left) left of \(total)", bundle: #bundle)
    }

    public func day(_ date: Date) -> String {
        DebtDates.day(date, calendar: calendar)
    }

    public func amount(_ value: Decimal, hidden: Bool) -> String {
        hidden ? DebtsViewModel.maskedAmount : formatter.string(from: value, currencyCode: debt.amount.currency)
    }

    var repayment: Decimal? {
        AmountInput.decimal(from: repaymentText)
    }

    /// Pointed out while typing, before the button is tapped.
    public var repaymentError: String? {
        if let repayment, repayment > debt.remaining {
            return String(localized: "That's more than what's left.", bundle: #bundle)
        }
        return errorMessage
    }

    public var canRepay: Bool {
        guard let repayment, !debt.isSettled, !isSaving else { return false }
        return repayment > 0 && repayment <= debt.remaining
    }

    public func repay() async {
        guard canRepay, let repayment else { return }
        let id = debt.id
        let today = now()
        await run { [useCases] in try await useCases.updateDebt.repay(id: id, amount: repayment, on: today) }
        if errorMessage == nil {
            repaymentText = ""
        }
    }

    public func settle() async {
        let id = debt.id
        let today = now()
        await run { [useCases] in try await useCases.updateDebt.settle(id: id, on: today) }
    }

    public func reopen() async {
        let id = debt.id
        await run { [useCases] in try await useCases.updateDebt.reopen(id: id) }
    }

    public func delete() async -> Bool {
        do {
            try await useCases.delete.deletePersonalDebt(id: debt.id)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't save the debt. Try again.", bundle: #bundle)
            return false
        }
    }

    private func run(_ work: @Sendable () async throws -> PersonalDebt) async {
        isSaving = true
        defer { isSaving = false }
        do {
            debt = try await work()
            errorMessage = nil
            didChange = true
        } catch {
            errorMessage = String(localized: "We couldn't save the debt. Try again.", bundle: #bundle)
        }
    }
}
