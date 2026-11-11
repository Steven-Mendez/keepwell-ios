import Core
import Domain
import Foundation
import GoalsDomain
import Observation
import SharedPresentation

/// Creates or edits a savings goal: its name, target, optional target month, icon and color.
/// What is set aside isn't edited here; "Add money" and "Withdraw" change it.
@MainActor
@Observable
public final class GoalEditorViewModel: Identifiable {
    public let id = UUID()
    /// `nil` while creating.
    public let editing: SavingsGoal?
    public private(set) var name = ""
    public var targetText: String {
        didSet { errorMessage = nil }
    }

    /// Fixed when editing: the money already set aside was counted in it.
    public var currency: String
    public let currencyOptions: [String]
    public var hasTargetMonth: Bool
    /// 1...12
    public var month: Int
    public var year: Int
    public var icon: String
    public var color: String?
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    let currentMonth: YearMonth
    private let saveGoal: any SaveSavingsGoalUseCase
    private let deleteGoal: (any DeleteSavingsGoalUseCase)?
    let calendar: Calendar

    public init(
        currencies: CurrencySettings,
        currentMonth: YearMonth,
        save: any SaveSavingsGoalUseCase,
        calendar: Calendar = .current,
    ) {
        editing = nil
        currency = currencies.principal
        currencyOptions = [currencies.principal] + (currencies.second.map { [$0] } ?? [])
        targetText = ""
        hasTargetMonth = false
        // Turning the date on starts at next month: a goal due this month has no time left to plan.
        let suggested = currentMonth.adding(months: 1)
        month = suggested.month
        year = suggested.year
        icon = SavingsGoalDisplay.defaultSymbol
        color = CategoryDisplay.colorChoices.first
        self.currentMonth = currentMonth
        saveGoal = save
        deleteGoal = nil
        self.calendar = calendar
    }

    public init(
        editing goal: SavingsGoal,
        currentMonth: YearMonth,
        save: any SaveSavingsGoalUseCase,
        delete: any DeleteSavingsGoalUseCase,
        calendar: Calendar = .current,
    ) {
        editing = goal
        name = goal.name
        targetText = CurrencyFormatter().number(goal.target.amount)
        currency = goal.target.currency
        currencyOptions = [goal.target.currency]
        hasTargetMonth = goal.targetMonth != nil
        let suggested = currentMonth.adding(months: 1)
        month = goal.targetMonth?.month ?? suggested.month
        year = goal.targetMonth?.year ?? suggested.year
        icon = SavingsGoalDisplay.symbol(for: goal)
        color = goal.color
        self.currentMonth = currentMonth
        saveGoal = save
        deleteGoal = delete
        self.calendar = calendar
    }

    public var isCreating: Bool {
        editing == nil
    }

    /// The currency picker only appears when creating with two currencies to choose from.
    public var showsCurrencyPicker: Bool {
        isCreating && currencyOptions.count > 1
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (AmountInput.decimal(from: targetText) ?? 0) > 0
            && !isSaving
    }

    /// Typing past the limit is cut here, so the field never shows text that won't be saved.
    public func setName(_ text: String) {
        name = String(text.prefix(SavingsGoal.maxNameLength))
        errorMessage = nil
    }

    /// Rewrites the typed target with grouping and two decimals once the field loses focus.
    public func formatTarget() {
        if let formatted = AmountInput.formatted(targetText) {
            targetText = formatted
        }
    }

    // MARK: Target month

    /// "December 2026", or "No date".
    public var targetMonthTitle: String {
        guard hasTargetMonth, let target = try? TargetMonth(month: month, year: year) else {
            return String(localized: "No date", bundle: #bundle)
        }
        return GoalDates.monthAndYear(target, calendar: calendar)
    }

    public var monthOptions: [(value: Int, title: String)] {
        (1 ... 12).map { ($0, GoalDates.monthName($0, calendar: calendar)) }
    }

    /// From this year (or the goal's own, if it's earlier) thirty years ahead.
    public var yearOptions: [Int] {
        let first = max(min(currentMonth.year, editing?.targetMonth?.year ?? currentMonth.year), TargetMonth.yearRange.lowerBound)
        let last = min(currentMonth.year + 30, TargetMonth.yearRange.upperBound)
        return Array(first ... max(first, last))
    }

    // MARK: Actions

    public func save() async -> SavingsGoal? {
        guard canSave, let amount = AmountInput.decimal(from: targetText) else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await saveGoal.execute(draft(target: amount))
            errorMessage = nil
            return saved
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    public var canDelete: Bool {
        editing != nil && deleteGoal != nil
    }

    public func delete() async -> Bool {
        guard let editing, let deleteGoal else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await deleteGoal.execute(id: editing.id)
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func draft(target amount: Decimal) -> SavingsGoalDraft {
        SavingsGoalDraft(
            id: editing?.id,
            name: name,
            target: Money(amount, currency),
            targetMonth: hasTargetMonth ? try? TargetMonth(month: month, year: year) : nil,
            icon: icon,
            color: color,
        )
    }

    static func message(for error: DomainError) -> String {
        switch error {
        case .missingName: String(localized: "Give the goal a name.", bundle: #bundle)
        case .invalidAmount: String(localized: "The target has to be greater than zero.", bundle: #bundle)
        default: String(localized: "We couldn't save the goal. Try again.", bundle: #bundle)
        }
    }
}
